############################################################################################
# Script for processing pre-auth subscriber information and caching into the Redis server. #
############################################################################################
use strict;
use warnings;
use vars qw(%RAD_REQUEST %RAD_CHECK);
use Redis;
use Authen::Radius;
use Config::Std { def_sep => '=' };
#use lib '/home/okis/perl5/lib/perl5';
use Log::Lite qw(logpath log);
use Data::Dumper;

# constant of FreeRADIUS module returned value
use constant RLM_MODULE_REJECT	=>	0;
use constant RLM_MODULE_OK	=>		2;
use constant RLM_MODULE_NOOP	=>	7;
use constant RLM_MODULE_UPDATED	=>	8;

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

# for storing redis server settings.
my %redisEnv;
# hash of storing Alu7750SR global settings.
my %aluEnv;

# global redis connection.
my $redis_con;
# calling sub to set up configuration environment variables.
setUpConfig();
# calling sub to set up redis connection. setUpRedisConn() must be called after setUpConfig().
setUpRedisConn();

# Read RADIUS CoA config Key-Value pairs.
my $port = $aluEnv{CoA}{PORT};
my $secret = $aluEnv{CoA}{SECRET};
my $timeout = $aluEnv{CoA}{TIMEOUT};
my $fwdSlaProf = $aluEnv{CoA}{FWD_SLA_PROF};
my $redSlaProf = $aluEnv{CoA}{RDT_SLA_PROF};
my $fwdSubscProf = $aluEnv{CoA}{FWD_SUB_PROF};
my $redSubscProf = $aluEnv{CoA}{RDT_SUB_PROF};

sub accounting {
	my $acct_status = $RAD_REQUEST{'Acct-Status-Type'};
	print "Origianl MAC: $RAD_REQUEST{'Calling-Station-Id'}\n";
	my $key = normalizeMAC($RAD_REQUEST{'Calling-Station-Id'});
	print "Normalized MAC: $key\n";
	if ($acct_status eq 'Start') {
		# To avoid sending CoA request to wrong subscriber, 
		# we'll send CoA DISCONNECT to gateway first if the MAC addr has already existed in Redis server.
		disconnect() if isKeyExists($key) == 1;
		# Caching pre-auth subscriber information from Accounting packet to hash in redis server.
		return RLM_MODULE_OK if setSubscHash($key) == 1;
		return RLM_MODULE_NOOP if setSubscHash($key) == 0;
	} elsif ($acct_status eq 'Stop') {
		# Clearing cached subscriber information from set in redis server.
		return RLM_MODULE_OK if delKey($key) == 1;
		return RLM_MODULE_NOOP if delKey($key) != 1;
	} else {
		# Do not process other types of Accounting.
		return RLM_MODULE_NOOP;
	}
}

sub log_err {
	my $errMsg = $_[0];
	log("error","subsc_cache","$errMsg");
}

sub setUpConfig {
	eval {
		# do something risky...
		read_config "$confpath/redis.cfg" => %redisEnv;
		read_config "$confpath/alu.cfg" => %aluEnv;
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

sub checkInput {
	if($ARGV[0] eq '-r'){
		return 1;
	}
	else{
		return 0;
	}
}

sub radiusSimulation {
	# Generate a list of MAC Addresses into the set for simulation test.
	#genMACList2Set(20);
	# Simulate hash value in FreeRADIUS.
	fillRADIUSVars();
	
	print "===MAC Cached Simulation Process START";
	printf "NAS-IP-Address: %s | Calling-Station-Id: %s | Acct-Status-Type: %s\n", 
		$RAD_REQUEST{'NAS-IP-Address'},$RAD_REQUEST{'Calling-Station-Id'}, $RAD_REQUEST{'Acct-Status-Type'};
	my $ret = accounting();
	if ($ret == 2) {
		# body...
		if ($RAD_REQUEST{'Acct-Status-Type'} eq 'Start') {
			# body...
			print "subscriber-$RAD_REQUEST{'Calling-Station-Id'} has been added into hash".Dumper $redis_con->hgetall($RAD_REQUEST{'Calling-Station-Id'})."\n";
		} else {
			# else...
			print "subscriber-$RAD_REQUEST{'Calling-Station-Id'} has been removed.\n";
		}
	} else {
		# else...
		print "Check if anything goes wrong!\n";
	}
	print "\n";
	print "===MAC Cached Simulation Process END\n";
}

sub fillRADIUSVars {
	%RAD_REQUEST = $redis_con->hgetall('RAD_REQUEST_ACCT_REDIR_START');
	%RAD_CHECK = $redis_con->hgetall('RAD_CHECK');
	#$RAD_REQUEST{'Calling-Station-Id'} = $redis_con->srandmember('rand_mac_list');
}

sub testFlow {
	my $key = $_[0];

	addRandElem2Set($key,5);
	my @members = getAllMembersFromSet($key);
	
	print "SET $key contains ".($#members+1)." members: \n";
	for(@members){
		print "$_\n";
	}
	my $randMember = getRandomMember($key);
	print "Clear $randMember from Set-$key successfully.\n" if removeMemFromSet($key,$randMember) == 1;
	@members = getAllMembersFromSet($key);
	print "SET $key contains ".($#members+1)." members: \n";
	for(@members){
		print "$_\n";
	}

	print "----------\n";
	$randMember = getRandomMember($key);
	print "Check member: $randMember if exist?\n";
	print "$randMember exists in set $key\n" if isMemberExist($key,$randMember) == 1;
}

sub addRandElem2Set {
	my $key = $_[0];
	my $num = $_[1];
	foreach (1..$num){
		my $umac = genRandomMAC('-');
		print "add member: $umac\n";
		$redis_con->sadd($key, $umac);
	}
}

sub addSubsc2Set {
	return 0 if @_ != 2;
	my $key = $_[0];
	my $member = $_[1];
	return 1 if $redis_con->sadd($key,$member) == 1;
}

sub genRandomMAC {
	my $sep = $_[0];
	my $case = $_[1];
	die "Too many arguments." if @_ > 2;
	$sep = '' if !defined($_[0]);
	my @chars = ('a'..'f','0'..'9');
	my $mac = '';
	for(my $i=1;$i<=6;$i++){
		my $seg = '';
		foreach(1..2){
			my $a = $chars[rand(@chars)];
			my $b = $chars[rand(@chars)];
			$seg = "$a$b";
			$seg = uc($seg) if $case eq 'uc';
			$seg = lc($seg) if $case eq 'lc';
		}
		$mac .= $seg if $i==1;
		$mac .= "$sep$seg" if $i>1;
	}
	return $mac;
}

sub genMACList2Set {
	my $num = $_[0];
	my $key = 'rand_mac_list';
	eval {
		# do something risky...
		for(my $i=0;$i<$num;$i++) {
			print "MAC: ".genRandomMAC('','lc')."\n";
			$redis_con->sadd($key, genRandomMAC('','lc'));	
		}
		return 1;
	};
	if ($@) {
		# handle failure...
		log_err("$@");
		return 0;
	}
	
}

sub getRandomMember {
	return 0 if @_ != 1;
	my $key = $_[0];
	my $randMember;
	$randMember = $redis_con->srandmember($key);
	return $randMember;
}

sub getAllMembersFromSet {
	return 0 if @_ != 1;
	my $key = $_[0];
	my @members;
	@members = $redis_con->smembers($key);
	return @members;
}

sub getAlcSubscID {
	my $key = $_[0];
	my $subscID;
	$subscID = $redis_con->hget($key,'Alc-Subsc-ID-Str');
	return $subscID;
}

sub removeMemFromSet {
	return 0 if @_ != 2;
	my $key = $_[0];
	my $member = $_[1];
	return 1 if $redis_con->srem($key,$member) == 1;
}

sub delKey {
	return 0 if @_ != 1;
	my $key = $_[0];
	return 1 if $redis_con->del($key) == 1;
}

sub isMemberExist {
	return 0 if @_ != 2;
	my $key = $_[0];
	my $member = $_[1];
	return 1 if $redis_con->sismember($key,$member) == 1;
}

sub isKeyExists {
	my $key = $_[0];
	print "isKeyExists: $key\n";
	#$key = normalizeMAC($key);
	return 1 if $redis_con->exists($key) == 1;
}

sub normalizeMAC {
	my $macAddr = $_[0];
	if($macAddr =~ /([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})[^0-9a-f]?([0-9a-f]{2})/) {
		$macAddr = lc("$1$2$3$4$5$6");
	}
	return $macAddr;
}

sub setSubscHash {
	return 0 if @_ != 1;
	my $key = $_[0];
	eval {
		# do something risky...
		foreach my $attr ( keys %{$aluEnv{'CachedAVP'}}) {
			if($aluEnv{'CachedAVP'}{"$attr"} eq '1') {
				my $ret = 0;
				print "adding $attr to cache...\n";

				print "value: $RAD_REQUEST{$attr}\n";
				$ret = $redis_con->hset($key, $attr => $RAD_REQUEST{$attr});
				print "add $attr fail.\n" if $ret != 1;
			}			
		}
	};
	if ($@) {
		# handle failure...
		log_err("$@");
		return 0;
	}
	print Dumper $redis_con->hgetall($key);
	return 1;
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
    log("coa", "SENT-COA-DICONNECT", "MAC CONFLICT", "$sent_attrs");

	my $type;
	$r->send_packet(DISCONNECT_REQUEST) and $type = $r->recv_packet();
	
	if($type == 41){
		log("coa", "RECV-COA-DICONNECT-ACK", "MAC CONFLICT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");
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
		log("coa", "RECV-COA-DICONNECT-NAK", "MAC CONFLICT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID", "$response_attrs");
		return 2;
	}
	else{
		log("coa", "RECV-COA-DICONNECT-TIMEOUT", "MAC CONFLICT", "$RAD_REQUEST{'Calling-Station-Id'}", "$RAD_REQUEST{'User-Name'}", "$subscID");
		return 3;
	}
}

###### For Test #######
my %RAD_REQUEST;
my %RAD_CHECK;
#die "INPUT: -r[random MAC]|KEY|MAC[must give without -r]|Acct-Status-Type\n" if scalar @ARGV < 3;
radiusSimulation();
#######################

=setUpRedisConn
=END
