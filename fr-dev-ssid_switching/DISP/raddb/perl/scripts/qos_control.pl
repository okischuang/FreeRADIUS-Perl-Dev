#################################################
#   Perl script for QoS control in FreeRADIUS   #
#################################################

use strict;
use vars qw(%RAD_REQUEST %RAD_REPLY %RAD_CHECK);
use Config::Std { def_sep => '=' };
use lib '/home/okis/perl5/lib/perl5';
use Log::Lite qw(logpath log);

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

# define global hash variables for storing config
my %qos;
my %coa;

setUpConfig();

#### Testing Block ####
use Redis;
use Data::Dumper;
my %RAD_REQUEST;
my %RAD_REPLY;
my %RAD_CHECK;
my %redisEnv;
# global redis connection.
my $redis_con;

setUpRedisConn();
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
	
	print "===QoS_control Simulation Process START";
	printf "NAS-IP-Address: %s | Calling-Station-Id: %s | User-Name: %s\n", 
		$RAD_REQUEST{'NAS-IP-Address'},$RAD_REQUEST{'Calling-Station-Id'}, $RAD_REQUEST{'User-Name'};
	my $ret = post_auth();
	if ($ret == 8) {
		# body...
		print "reply list is updated.\n";
		printDebugInfo();
	} 
	elsif($ret == 2) {
		print "reply list is not updated. something went wrong!\n";
	}
	else {
		# else...
		print "Check if anything goes wrong!\n";
	}
	print "\n";
	print "===QoS_control Simulation Process END\n";
}
#### Testing Block ####



sub log_err {
	my $errMsg = $_[0];
	log("error","QoS_control","$errMsg");
}

sub setUpConfig {
	eval {
		# do something risky...
		read_config "$confpath/wispr_qos.cfg" => %qos;
		read_config "$confpath/alu.cfg" => %coa;
		read_config "$confpath/redis.cfg" => %redisEnv;
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
			server => "$s1_ip:$s1_port",
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

sub post_auth {
	my $ret = setQoS();
	return RLM_MODULE_UPDATED if $ret == 1;
	return RLM_MODULE_OK if $ret != 1;
}

sub setQoS {
	# check if reading config file successfully
	if(%qos) {
		my $realm_section = $RAD_REQUEST{'FreeRADIUS-WiFi-Realm'};
		my $gw_type = $RAD_CHECK{'Gateway-Type'};
		my $isEAPSIM = exists($RAD_REQUEST{'EAP-Message'}) ? 1 : 0;
		# if something goes wrong...even though it should not happend
		if($realm_section eq "") {
			$realm_section = 'Default';
			if($gw_type eq 'ALU' && $isEAPSIM == 1) {
				setEAPSIMQoS($realm_section, '1');
			}
			else{
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = $qos{"$realm_section"}{up}*1000;      
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = $qos{"$realm_section"}{down}*1000;
				$RAD_REPLY{'Idle-Timeout'} = $qos{"$realm_section"}{ito};
				$RAD_REPLY{'Session-Timeout'} = $qos{"$realm_section"}{sto};
			}
			return 1;
		}	

		my $override = $qos{"$realm_section"}{override};
		my ($burst, $upRate, $downRate, $ito, $sto, $li_Dest);
		
		if($override eq 1){
			if($gw_type eq 'ALU' && $isEAPSIM == 1) {
				setEAPSIMQoS($realm_section, $override);
			}
			else{
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = $qos{"$realm_section"}{up}*1000;      
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = $qos{"$realm_section"}{down}*1000;
				$RAD_REPLY{'Idle-Timeout'} = $qos{"$realm_section"}{ito};
				$RAD_REPLY{'Session-Timeout'} = $qos{"$realm_section"}{sto};
			}
			# Here we can force setting WISPr-Rediection-URL according to the value set in every realm section appearing the wispr_qos.cfg 
			if($qos{"$realm_section"}{url} ne '') {
				$RAD_REPLY{'WISPr-Redirection-URL'} = $qos{"$realm_section"}{url};
			}
			return 1;
		}
		else {
			# Check if unlimited bandwidth or not?
			if($RAD_REPLY{'WISPr-Bandwidth-Max-Up'} eq "0" || $RAD_REPLY{'WISPr-Bandwidth-Max-Down'} eq "0") {
				# This is unlimited profile.");
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = 200000000;
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = 100000000;
				if($gw_type eq 'ALU'){
					$upRate = "i:p:1:pir=".$RAD_REPLY{'WISPr-Bandwidth-Max-Up'}.",mbs=".$qos{Global}{burst};
					$downRate = "e:q:1:pir=".$RAD_REPLY{'WISPr-Bandwidth-Max-Down'};
					my @ratelimit = ($upRate, $downRate);
					$RAD_REPLY{'Alc-Subscriber-QoS-Override'} = \@ratelimit;
				}
			}
			# Check if Bandwidth AVP is available?
			if(!defined $RAD_REPLY{'WISPr-Bandwidth-Max-Up'} || !defined $RAD_REPLY{'WISPr-Bandwidth-Max-Down'}) {
				# Missing Rate Limit Qos value from AAA. Apply --Default-- profile
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = $qos{Default}{up}*1000;      
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = $qos{Default}{down}*1000;
				if($gw_type eq 'ALU'){
					$upRate = "i:p:1:pir=".$RAD_REPLY{'WISPr-Bandwidth-Max-Up'}.",mbs=".$qos{Global}{burst};
					$downRate = "e:q:1:pir=".$RAD_REPLY{'WISPr-Bandwidth-Max-Down'};
					my @ratelimit = ($upRate, $downRate);
					$RAD_REPLY{'Alc-Subscriber-QoS-Override'} = \@ratelimit;	
				}
			}
			# Check if timeout constraints is available?
			if(!defined $RAD_REPLY{'Idle-Timeout'} || !defined $RAD_REPLY{'Session-Timeout'}) {
				# Missing Timeout Qos value from AAA. Apply --Default-- profile
				$RAD_REPLY{'Idle-Timeout'} = $qos{Default}{ito};
				if($gw_type eq 'ALU') {
					$RAD_REPLY{'Alc-Relative-Session-Timeout'} = $qos{Default}{sto};
				}
				else {
					$RAD_REPLY{'Session-Timeout'} = $qos{Default}{sto};
				}
			}
			#
			if($gw_type eq 'ALU' && $isEAPSIM == 1) {
				# here, it will only set Alc-SLA-Prof-Str, Alc-Subsc-Prof-Str, Framed-Pool
				setEAPSIMQoS($realm_section, $override);
				return 1;
			}
			return 1;
		}
	}
	else{
		log_err("QoS env vars is not available. Use ");
		$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = 20488000;
		$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = 5048000;
		$RAD_REPLY{'Idle-Timeout'} = 600;
		$RAD_REPLY{'Session-Timeout'} = 14400;
		return 1;
	}
}

# 
# @param: realm, isOverride
#
sub setEAPSIMQoS {
	my $realm_section = $_[0];
	my $override = $_[1];
	my $gw_type = $RAD_CHECK{'Gateway-Type'};
	my $isEAPSIM = exists($RAD_REQUEST{'EAP-Message'}) ? 1 : 0;
	my $isNAT = $RAD_CHECK{'Is-NAT'};
	my $fwdSlaProf = $coa{EAP}{FWD_SLA_PROF};
	my $framedPool = $coa{EAP}{FRAMED_POOL};
	my $subscProf = $coa{EAP}{SUBSC_PROF};
	my ($burst, $upRate, $downRate);
	$burst = $qos{Global}{burst};
	if($override eq '1') {
		$upRate = POSIX::floor($qos{"$realm_section"}{up});
		$downRate = POSIX::floor($qos{"$realm_section"}{down});
		$upRate = "i:p:1:pir=$upRate,mbs=$burst";
		$downRate = "e:q:1:pir=$downRate";
		my @ratelimit = ($upRate, $downRate);
		$RAD_REPLY{'Alc-Subscriber-QoS-Override'} = \@ratelimit;
		$RAD_REPLY{'Idle-Timeout'} = $qos{"$realm_section"}{ito};
		$RAD_REPLY{'Alc-Relative-Session-Timeout'} = $qos{"$realm_section"}{sto};
	}
	# No matter does the $override equal to '1' or not, we'll set following profile AVPs as long as $isNAT doesn't equal to 'Yes'.
	if($isNAT ne 'Yes') {
		$RAD_REPLY{'Alc-SLA-Prof-Str'} = "$fwdSlaProf";
        $RAD_REPLY{'Alc-Subsc-Prof-Str'} = "$subscProf";
        $RAD_REPLY{'Framed-Pool'} = "$framedPool";
	}
}


