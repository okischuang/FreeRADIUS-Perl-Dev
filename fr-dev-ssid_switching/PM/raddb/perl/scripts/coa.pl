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
use Redis;
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
# For test: /var/log/radius
my $logdir = '/var/log/radius';
# For Prod: /hinet/freeradius/var/log/radius/perl
#my $logdir = '/hinet/freeradius/var/log/radius/perl';
logpath("$logdir");

# define root path where we read our configurations.
# For Test: /Users/okischuang/Documents/Dev/fr-dev-ssid_switching/DISP/raddb/perl/conf
my $confpath = '/Users/okischuang/Documents/Dev/fr-dev-ssid_switching/DISP/raddb/perl/conf';
# For Prod: /hinet/freeradius/etc/raddb/perl/conf
#my $confpath = '/hinet/freeradius/etc/raddb/perl/conf';

# define FreeRADIUS dictionary directory.
# For Test: /Users/okischuang/Documents/Dev/fr-dev-ssid_switching/DISP/share/freeradius
my $dictpath = '/Users/okischuang/Documents/Dev/fr-dev-ssid_switching/DISP/share/freeradius';
# For Prod: /hinet/freeradius/share/freeradius
#my $dictpath = '/hinet/freeradius/share/freeradius';

# define global hash variables for storing config
my %redisEnv;
my %qos;
my %coa;

# global redis connection.
my $redis_con;

setUpConfig();
setUpRedisConn();

# Read RADIUS CoA config Key-Value pairs.
my $port = $coa{CoA}{PORT};
my $secret = $coa{CoA}{SECRET};
my $timeout = $coa{CoA}{TIMEOUT};
my $fwdSlaProf = $coa{CoA}{FWD_SLA_PROF};
my $redSlaProf = $coa{CoA}{RDT_SLA_PROF};
my $fwdSubscProf = $coa{CoA}{FWD_SUB_PROF};
my $redSubscProf = $coa{CoA}{RDT_SUB_PROF};

#### Testing Block ####
use Data::Dumper;
my %RAD_REQUEST;
my %RAD_REPLY;
my %RAD_CHECK;

radiusSimulation();

sub fillRADIUSVars {
	%RAD_REQUEST = $redis_con->hgetall('RAD_REQUEST_AUTH_EAP');
	%RAD_CHECK = $redis_con->hgetall('RAD_CHECK');
}
sub printDebugInfo {
	print "Session-Timeout: $RAD_REPLY{'Session-Timeout'}\n" if $RAD_CHECK{'Gateway-Type'} ne 'ALU';
	print "Alc-Relative-Session-Timeout: $RAD_REPLY{'Alc-Relative-Session-Timeout'}\n" if $RAD_CHECK{'Gateway-Type'} eq 'ALU';
	print "Idle-Timeout: $RAD_REPLY{'Idle-Timeout'}\n";
	print "WISPr-Bandwidth-Max-Up: $RAD_REPLY{'WISPr-Bandwidth-Max-Up'}\n" if $RAD_CHECK{'Gateway-Type'} ne 'ALU';
	print "WISPr-Bandwidth-Max-Down: $RAD_REPLY{'WISPr-Bandwidth-Max-Down'}\n" if $RAD_CHECK{'Gateway-Type'} ne 'ALU';
	print "Alc-Subscriber-QoS-Override: $RAD_REPLY{'Alc-Subscriber-QoS-Override'}[0]\n" if $RAD_CHECK{'Gateway-Type'} eq 'ALU';
	print "Alc-Subscriber-QoS-Override: $RAD_REPLY{'Alc-Subscriber-QoS-Override'}[1]\n" if $RAD_CHECK{'Gateway-Type'} eq 'ALU';
	print "Framed-Pool: $RAD_REPLY{'Framed-Pool'}\n" if $RAD_CHECK{'Is-NAT'} ne 'Yes';
	print "Alc-SLA-Prof-Str: $RAD_REPLY{'Alc-SLA-Prof-Str'}\n" if $RAD_CHECK{'Is-NAT'} ne 'Yes';
	print "Alc-Subsc-Prof-Str: $RAD_REPLY{'Alc-Subsc-Prof-Str'}\n" if $RAD_CHECK{'Is-NAT'} ne 'Yes';
}
sub radiusSimulation {
	# Simulate hash value in FreeRADIUS.
	fillRADIUSVars();
	
	print "===CoA Simulation Process START";
	printf "NAS-IP-Address: %s | Calling-Station-Id: %s | User-Name: %s | Alc-Subsc-ID-Str: %s\n", 
		$RAD_REQUEST{'NAS-IP-Address'},$RAD_REQUEST{'Calling-Station-Id'}, $RAD_REQUEST{'User-Name'}, getAlcSubscID(normalizeMAC($RAD_REQUEST{'Calling-Station-Id'}));
	my $ret = post_auth();
	if($ret == 2) {
		print "CoA succeeded!\n";

	}
	else {
		# else...
		print "Check if anything goes wrong!\n";
	}
	print "\n";
	print "===CoA Simulation Process END\n";
}
#### Testing Block ####


sub log_err {
	my $errMsg = $_[0];
	log("error","coa","$errMsg");
}

sub setUpConfig {
	eval {
		# do something risky...
		read_config "$confpath/redis.cfg" => %redisEnv;
		read_config "$confpath/wispr_qos.cfg" => %qos;
		read_config "$confpath/alu.cfg" => %coa;
		# Load FreeRADIUS attributes from specified directory.
		Authen::Radius->load_dictionary("$dictpath/dictionary");
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
	$subscID = $redis_con->hget($key,'Alc-Subsc-ID-Str');
	return $subscID;
}

sub isKeyExists {
	my $key = $_[0];
	$key = normalizeMAC($key);
	return 1 if $redis_con->exists($key) == 1;
}

sub normalizeMAC {
	my $macAddr = $_[0];
	if($macAddr =~ /([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})/) {
		$macAddr = lc("$1$2$3$4$5$6");
	}
}

sub getAuthenRadiusInstance {
	my $host = $_[0];
	my $secret = $_[1];
	my $to = $_[2];
	my $r;
	eval {
		# do something risky...
		$r = new Authen::Radius(Host => $host, Secret => $secret, TimeOut => $to);
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
	my $ret = 0;
	$ret = forwarding();
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
    if($RAD_REQUEST{'NAS-IP-Address'} eq ""){
            log_err("COA-FAIL, NAS-IP-Address is not found");
            return 0;
    }

    # Piecing NAS-IP-Address and port together into the host address of CoA server.
    my $host = "$RAD_REQUEST{'NAS-IP-Address'}:$port";
    # New a RADIUS object.
    my $r = getAuthenRadiusInstance($host,$secret,$timeout);
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
	$fake_sto = $qos{Global}{alu_fake_sto};
	
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
	$subscID = getAlcSubscID(normalizeMAC($RAD_REQUEST{'Calling-Station-Id'}));
	
	$r->add_attributes (
		{ Name => 'Alc-Subsc-ID-Str', Value => $subscID},
		{ Name => 'NAS-Port', Value => $RAD_REQUEST{'NAS-Port'}},
		{ Name => 'User-Name', Value => $RAD_REQUEST{'User-Name'}},
		{ Name => 'Alc-SLA-Prof-Str', Value => $fwdSlaProf},
		{ Name => 'Alc-Subscriber-QoS-Override', Value => $upRate},
		{ Name => 'Alc-Subscriber-QoS-Override', Value => $downRate},
		{ Name => 'Alc-Relative-Session-Timeout', Value => $fake_sto},
		{ Namw => 'Acct-Interim-Interval', Value => $sto},
		{ Name => 'Idle-Timeout', Value => $ito}
	);
	# iterates every element of Class array out and adds it into attributes object.
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

	# concatenate each AVP to a string for log printing.
	my $sent_attrs = "";
	for $a ($r->get_attributes()) {
		if($sent_attrs ne ""){
			$sent_attrs .= "&$a->{'Name'}=$a->{'Value'}";
		}
		else{
			$sent_attrs = "$a->{'Name'}=$a->{'Value'}"
		}
	}
	log("coa", "SENT-COA-FWD", "$sent_attrs");

	# send CoA packet to CoA server.
	my $type;	
	$r->send_packet(COA_REQUEST, 3) and $type = $r->recv_packet();

	# Decide what to do by returned value from CoA server
	if($type == 44){
		if($RAD_REPLY{'Alc-LI-Action'}) {
			my $li_input = "Alc-Subsc-ID-Str=$subscID,Alc-LI-Action=$RAD_REPLY{'Alc-LI-Action'},Alc-LI-Destination=$li_Dest";
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
    my $r = getAuthenRadiusInstance($host,$secret,$timeout);
    return 0 if $r == 0;
	my $fake_sto = 86400; # use of keeping IP of subscriber host on GW in a day.
	
	my $subscID;
	$subscID = getAlcSubscID(normalizeMAC($RAD_REQUEST{'Calling-Station-Id'}));
	$subscID = $RAD_REQUEST{'Alc-Subsc-ID-Str'} if $subscID eq '';

	# set up AVPs which we need for sending CoA. The key is 'Alc-Subsc-ID-Str'.
	$r->add_attributes (
		{ Name => 'Alc-Subsc-ID-Str', Value => $subscID},
		{ Name => 'Acct-Interim-Interval', Value => $fake_sto},
		{ Name => 'Alc-SLA-Prof-Str', Value => $redSlaProf}
	);

	# concatenate each AVP to a string for log printing.
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
		log("coa", "RECV-COA-RDT-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");	
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
		log("coa", "RECV-COA-RDT-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID", "$response_attrs");
		return 2;
	}
	else{
		log("coa", "RECV-COA-RDT-TIMEOUT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");
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
    my $r = getAuthenRadiusInstance($host,$secret,$timeout);
    return 0 if $r == 0;

    my $subscID;
	$subscID = getAlcSubscID(normalizeMAC($RAD_REQUEST{'Calling-Station-Id'}));
	$subscID = $RAD_REQUEST{'Alc-Subsc-ID-Str'} if $subscID eq '';

	$r->add_attributes (
		{ Name => 'Alc-Subsc-ID-Str', Value => $subscID}
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
		log("coa", "RECV-COA-DICONNECT-ACK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");
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
		log("coa", "RECV-COA-DICONNECT-NAK", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID", "$response_attrs");
		return 2;
	}
	else{
		log("coa", "RECV-COA-DICONNECT-TIMEOUT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");
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
