############################################################################
# 									   									   #								 
# Script of sending RADIUS CoA request to CoA server to change SLA profile #
# This version if specific to CHT Wi-Fi Dispatcher. It can only executed   #
# while in section "post_auth" and only support forwarding function.       #
#
############################################################################
use strict;
use vars qw(%RAD_REQUEST %RAD_REPLY %RAD_CHECK);
use Authen::Radius;
use POSIX qw/strftime/;
use Encode qw(encode decode);
use Config::Std { def_sep => '=' };
use Log::Lite qw(logpath log);
#use Digest::MD5;

#
# This the remapping of return values
#
use constant    RLM_MODULE_REJECT=>    0;#  /* immediately reject the request */
use constant	RLM_MODULE_FAIL=>      1;#  /* module failed, don't reply */
use constant	RLM_MODULE_OK=>        2;#  /* the module is OK, continue */
use constant	RLM_MODULE_HANDLED=>   3;#  /* the module handled the request, so stop. */
use constant	RLM_MODULE_INVALID=>   4;#  /* the module considers the request invalid. */
use constant	RLM_MODULE_USERLOCK=>  5;#  /* reject the request (user is locked out) */
use constant	RLM_MODULE_NOTFOUND=>  6;#  /* user not found */
use constant	RLM_MODULE_NOOP=>      7;#  /* module succeeded without doing anything */
use constant	RLM_MODULE_UPDATED=>   8;#  /* OK (pairs modified) */
use constant	RLM_MODULE_NUMCODES=>  9;#  /* How many return codes there are */

# Same as src/include/radiusd.h
use constant	L_DBG=>   1;
use constant	L_AUTH=>  2;
use constant	L_INFO=>  3;
use constant	L_ERR=>   4;
use constant	L_PROXY=> 5;
use constant	L_ACCT=>  6;

# Set up logfile directory 
my $logdir = '/hinet/freeradius/var/log/radius/perl';
logpath("$logdir");

# Open and read the config file.
my %redisEnv;
my %qos;
my %coa;

setUpConfig();
setUpRedisConn();

sub log_err {
	my $errMsg = $_[0];
	logpath("$logdir");
	log("error","coa","$errMsg");
}

sub setUpConfig {
	eval {
		# do something risky...
		read_config "$confpath/redis.cfg" => %redisEnv;
		read_config '/hinet/freeradius/etc/raddb/perl/conf/wispr_qos.cfg' => %qos;
		read_config '/hinet/freeradius/etc/raddb/perl/conf/alu.cfg' => %coa;
		# Load FreeRADIUS attributes from specified directory.
		Authen::Radius->load_dictionary('/hinet/freeradius/share/freeradius/dictionary');
	};
	if ($@) {
		# handle failure...
		log_err("$@");
	}
}

sub setUpRedisConn {
	my $s1_ip = $redisEnv{'Server1'}{'host'};
	my $s1_port = $redisEnv{'Server1'}{'port'};
	my $s1_reconn = $redisEnv{'Server1'}{'reconnect'};
	eval {
		# try to get a connection from Redis server.
		$redis_con = Redis->new(
			sever => "$s1_ip:$s1_port",
			reconnect => 3,
			name => 'conn_subsc_cache',
		);
	};
	if ($@) {
		# handle failure...
		log_err("$@");
		# try to connect Server2
	}
}

sub getAlcSubscID {
	my $key = $_[0];
	my $subscID;
	$subscID = $redis_con->hget($key,'Alc-Subsc-ID');
	return $subscID;
}

sub isKeyExists {
	my $key = $_[0];
	return 1 if $redis_con->exists($key) == 1;
}

sub getAuthenRadiusInstance {
	my $host = $_[0];
	my $secret = $_[1];
	my $r;
	eval {
		# do something risky...
		$r = new Authen::Radius(Host => $host, Secret => $secret);
	};
	if ($@) {
		# handle failure...
		log_err("$@");
		return 0;
	}
	return $r;
}

# Function to handle post_auth
sub post_auth {
	# check if MAC address exists in Redis.
	return RLM_MODULE_NOOP unless isKeyExists == 1;
	my $ret = 0;
	$ret = &forwarding;
	if($ret == 0){return RLM_MODULE_NOOP;}
	elsif($ret == 1){
		$RAD_REPLY{'Reply-Message'} = "0";
		return RLM_MODULE_OK;
	}
	elsif($ret == 2){
		$RAD_REPLY{'Reply-Message'} = "99";
		return RLM_MODULE_OK;
	}
	elsif($ret == 3){
		$RAD_REPLY{'Reply-Message'} = "99";
		return RLM_MODULE_OK;
	}
	else{return RLM_MODULE_NOOP;}
}

sub accounting {
	if($RAD_REQUEST{'User-Name'} eq 'weblogout') {
		my $ret = 0;
		$ret = &redirecting;
		if($ret == 0){return RLM_MODULE_NOOP;}
		elsif($ret == 1){
			$RAD_REPLY{'Reply-Message'} = "0";
			return RLM_MODULE_OK;
		}
		elsif($ret == 2){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		elsif($ret == 3){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		else{return RLM_MODULE_NOOP;}
	}
	elsif($RAD_REQUEST{'User-Name'} eq 'disconnect') {
		my $ret = 0;
		$ret = &disconnect;
		if($ret == 0){return RLM_MODULE_NOOP;}
		elsif($ret == 1){
			$RAD_REPLY{'Reply-Message'} = "0";
			return RLM_MODULE_OK;
		}
		elsif($ret == 2){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		elsif($ret == 3){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		else{return RLM_MODULE_NOOP;}

	}
	elsif($RAD_REQUEST{'Acct-Status-Type'} eq 'Interim-Update' && $RAD_REQUEST{'Alc-SLA-Prof-Str'} eq $fwdSlaProf) {
		my $ret = 0;
		$ret = &redirecting;
		if($ret == 0){return RLM_MODULE_NOOP;}
		elsif($ret == 1){
			$RAD_REPLY{'Reply-Message'} = "0";
			return RLM_MODULE_OK;
		}
		elsif($ret == 2){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		elsif($ret == 3){
			$RAD_REPLY{'Reply-Message'} = "99";
			return RLM_MODULE_OK;
		}
		else{return RLM_MODULE_NOOP;}

        }
}
sub forwarding {
	# Read RADIUS CoA config Key-Value pairs.
	my $port = $coa{CoA}{PORT};
	my $secret = $coa{CoA}{SECRET};
	my $fwdSlaProf = $coa{CoA}{FWD_SLA_PROF};
	my $redSlaProf = $coa{CoA}{RDT_SLA_PROF};
	my $fwdSubscProf = $coa{CoA}{FWD_SUB_PROF};
	my $redSubscProf = $coa{CoA}{RDT_SUB_PROF};

    if($RAD_REQUEST{'NAS-IP-Address'} eq ""){
            log_err("COA-FAIL, NAS-IP-Address is not found");
            return 0;
    }

    # Piecing NAS-IP-Address and port together into the host address of CoA server.
    my $host = "$RAD_REQUEST{'NAS-IP-Address'}:$port";
    # New a RADIUS object.
    my $r = getAuthenRadiusInstance($host,$secret);
    return 0 if $r == 0;

    # Check if %qos exists or not?
	if(!%qos) {
		log_err("lack of qos config");
		return 0;
	}

	my $realm_section = $RAD_REQUEST{'FreeRADIUS-WiFi-Realm'};
	my ($subscID, $burst, $upRate, $downRate, $ito, $sto, $fake_sto, $li_Dest);
	$burst = $qos{Global}{burst};	
	$li_Dest = $qos{Global}{li_dest};
	
	if($qos{"$realm_section"}{override} eq 1){
		$upRate = POSIX::floor($qos{"$realm_section"}{up});
		$downRate = POSIX::floor($qos{"$realm_section"}{down});
		$ito = $qos{"$realm_section"}{ito};
		$sto = $qos{"$realm_section"}{sto};
	}
	else {
		# divide 1k with bandwidth up/down representing as mbps 
		$upRate = POSIX::floor($RAD_REPLY{'WISPr-Bandwidth-Max-Up'}/1000);
		$downRate = POSIX::floor($RAD_REPLY{'WISPr-Bandwidth-Max-Down'}/1000);
		$ito = $RAD_REPLY{'Idle-Timeout'}; 
		$sto = $RAD_REPLY{'Session-Timeout'};
		# if either Up or Down bandwidth limit value is missing, we try to find out the value corresponding its realm.
		# we finally pick Deafult qos value if qos value of the realm can't be found.
		if($upRate == 0 || $downRate == 0) {
			if($qos{"$realm_section"}{up} ne ""){
				$upRate = POSIX::floor($qos{"$realm_section"}{up});      
			}
			else{
				$upRate = POSIX::floor($qos{"Default"}{up});
			}
			if($qos{"$realm_section"}{down} ne ""){
				$downRate = POSIX::floor($qos{"$realm_section"}{down});
			}
			else{
				$upRate = POSIX::floor($qos{"Default"}{down});
			}
		}
		# do the same thing with the timeout control parameters.
		if($ito == 0 || $sto == 0) {
			if($qos{"$realm_section"}{ito} ne ""){
            	$ito = $qos{"$realm_section"}{ito};
            }
            else{
				$ito = $qos{Default}{ito};
            }
            if($qos{"$realm_section"}{down} ne ""){
                    $sto = $qos{"$realm_section"}{sto};
            }
            else{
            	$sto = $qos{Default}{sto};
            }
		}
	}

	$upRate = "i:p:1:pir=$upRate,mbs=$burst";
	$downRate = "e:q:1:pir=$downRate";
	$subscID = getAlcSubscID();
	
	$r->add_attributes (
		{ Name => 'Alc-Subsc-ID', Value => $subscID},
		{ Name => 'NAS-Port', Value => $RAD_REQUEST{'NAS-Port'}},
		{ Name => 'User-Name', Value => $RAD_REQUEST{'User-Name'}},
		{ Name => 'Alc-SLA-Prof-Str', Value => $fwdSlaProf},
		{ Name => 'Alc-Subscriber-QoS-Override', Value => $upRate},
		{ Name => 'Alc-Subscriber-QoS-Override', Value => $downRate},
		{ Name => 'Alc-Relative-Session-Timeout', Value => $sto},
		{ Name => 'Idle-Timeout', Value => $ito}
	);
	if(ref($RAD_REPLY{'Class'}) eq 'ARRAY') {
        foreach (@{$RAD_REPLY{'Class'}} ) {
                $r->add_attributes (
                        { Name => 'Class', Value => $_}
                );
        }
    }
    else{
        $r->add_attributes (
                { Name => 'Class', Value => $RAD_REPLY{'Class'}}
        );
    }

	# if internal attr "Is-LI-Enable" exists, add LI related attr.
	my $sent_attrs = "";
	for $a ($r->get_attributes()) {
		if($sent_attrs ne ""){
			$sent_attrs .= "\t$a->{'Name'}=$a->{'Value'}";
		}
		else{
			$sent_attrs = "$a->{'Name'}=$a->{'Value'}"
		}
	}
	log("coa", "SENT-COA-FWD", "$sent_attrs");

	my $type;	
	$r->send_packet(COA_REQUEST, 3) and $type = $r->recv_packet();

	if($type == 44){
		if($RAD_REPLY{'Alc-LI-Action'}) {
			my $li_input = "Alc-Subsc-ID=$subscID,Alc-LI-Action=$RAD_REPLY{'Alc-LI-Action'},Alc-LI-Destination=$li_Dest";
			log("coa", "SENT-COA-LI", "$RAD_REQUEST{'Calling-Station-Id'}", "$li_input");
			my $li_output = &call_radclient($li_input,$host,"coa","$secret");
			if($li_output == 1) {
				log("coa", "RECV-COA-LI-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
			}
			elsif($li_output == 2) {
				log("coa", "RECV-COA-LI-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
			}
			else{
				log("coa", "RECV-COA-LI-FAIL", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
			}
		}
		log("coa", "RECV-COA-FWD-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
		return 1;
	}
	elsif($type == 45){
		my $response_attrs = "";
		for $a ($r->get_attributes()) {
	        if($response_attrs ne ""){
	                $response_attrs .= "\t$a->{'Name'}=$a->{'Value'}";
	        }
	        else{
	                $response_attrs = "$a->{'Name'}=$a->{'Value'}"
	        }
	    }
		log("coa", "RECV-COA-FWD-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$response_attrs");
		return 2;
	}
	else {
		log("coa", "RECV-COA-FWD-TIMEOUT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
		return 3;
	}
}
sub redirecting {
	if($RAD_REQUEST{'NAS-IP-Address'} eq ""){
                log("coa","COA-FAIL","NAS-IP-Address Not Found");
                return 0;
        }
        my $host = "$RAD_REQUEST{'NAS-IP-Address'}:$port";
        # New a RADIUS object.
        my $r = new Authen::Radius(Host => $host, Secret => $secret);
	my $fake_sto = 86400; # use of keeping IP of subscriber host on GW in a day.
	
	$r->add_attributes (
			{ Name => 'NAS-Port-Id', Value => $RAD_REQUEST{'NAS-Port-Id'}},
			{ Name => 'Framed-IP-Address', Value => $RAD_REQUEST{'Framed-IP-Address'}},
			{ Name => 'Acct-Interim-Interval', Value => $fake_sto},
			{ Name => 'Alc-SLA-Prof-Str', Value => $redSlaProf}
	);

	my $sent_attrs = "";
        for $a ($r->get_attributes()) {
                if($sent_attrs ne ""){
                        $sent_attrs .= "\t$a->{'Name'}=$a->{'Value'}";
                }
                else{
                        $sent_attrs = "$a->{'Name'}=$a->{'Value'}"
                }
        }
        log("coa", "SENT-COA-RDT", "$sent_attrs");
	my $type;
	$r->send_packet(COA_REQUEST) and $type = $r->recv_packet();
	if($type == 44){
		log("coa", "RECV-COA-RDT-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");	
		return 1;
	}
	elsif($type == 45){
		my $response_attrs = "";
                for $a ($r->get_attributes()) {
                        if($response_attrs ne ""){
                                $response_attrs .= "$a->{'Name'}=\t$a->{'Value'}";
                        }
                        else{
                                $response_attrs = "$a->{'Name'}=$a->{'Value'}"
                        }
                }
		log("coa", "RECV-COA-RDT-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}","$response_attrs");
		return 2;
	}
	else{
		log("coa", "RECV-COA-RDT-TIMEOUT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
		return 3;
	}
}	
sub disconnect {
	if($RAD_REQUEST{'NAS-IP-Address'} eq ""){
                log("coa","COA-FAIL","NAS-IP-Address Not Found");
                return 0;
        }
        my $host = "$RAD_REQUEST{'NAS-IP-Address'}:$port";
        # New a RADIUS object.
        my $r = new Authen::Radius(Host => $host, Secret => $secret);
	$r->add_attributes (
			{ Name => 'NAS-Port-Id', Value => $RAD_REQUEST{'NAS-Port-Id'}},
			{ Name => 'Framed-IP-Address', Value => $RAD_REQUEST{'Framed-IP-Address'}},
			);

	my $sent_attrs = "";
        for $a ($r->get_attributes()) {
                if($sent_attrs ne ""){
                        $sent_attrs .= "\t$a->{'Name'}=$a->{'Value'}";
                }
                else{
                        $sent_attrs = "$a->{'Name'}=$a->{'Value'}"
                }
        }
        log("coa", "SENT-COA-DICONNECT", "$sent_attrs");
	my $type;
	$r->send_packet(DISCONNECT_REQUEST) and $type = $r->recv_packet();
	if($type == 41){
		log("coa", "RECV-COA-DICONNECT-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
		return 1;
	}
	elsif($type == 42){
		my $response_attrs = "";
                for $a ($r->get_attributes()) {
                        if($response_attrs ne ""){
                                $response_attrs .= "\t$a->{'Name'}=$a->{'Value'}";
                        }
                        else{
                                $response_attrs = "$a->{'Name'}=$a->{'Value'}"
                        }
                }
		log("coa", "RECV-COA-DICONNECT-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$response_attrs");
		return 2;
	}
	else{
		log("coa", "RECV-COA-DICONNECT-TIMEOUT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}");
		return 3;
	}
}
#
# Parameter: $input, $hot, $type, $secret
#
sub call_radclient {
	my $input = $_[0];
	my $host=$_[1];
	my $type=$_[2];
	my $secret=$_[3];
	my $cmd = "echo $input | /opt/freeradius/bin/radclient $host $type $secret";
	my $output = qx/$cmd/;
	if($output =~ /code 44/){
		return 1;
	}
	elsif($output =~ /code 45/){
		return 2;
	}
	else{
		return 0;
	}
}
