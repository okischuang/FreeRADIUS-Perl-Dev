############################################################################################
# Script for processing pre-auth subscriber information and caching into the Redis server. #
############################################################################################
use strict;
use warnings;
use vars qw(%RAD_REQUEST %RAD_CHECK);
use Redis;
use Config::Std { def_sep => '=' };
#use lib '/home/okis/perl5/lib/perl5';
use Log::Lite qw(logpath log);
use Data::Dumper;

# constant of FreeRADIUS module returned value
use constant RLM_MODULE_REJECT	=>	0;
use constant RLM_MODULE_OK	=>		2;
use constant RLM_MODULE_NOOP	=>	7;
use constant RLM_MODULE_UPDATED	=>	8;

# define root path where we write our logs.
my $logpath = '/var/log/radius';
logpath("$logpath");
# define root path where we read our configurations.
my $confpath = '/Users/okischuang/Documents/Dev/freeradius/conf';
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

sub accounting {
	my $acct_status = $RAD_REQUEST{'Acct-Status-Type'};
	my $key = $RAD_REQUEST{'Calling-Station-Id'};

	if ($acct_status eq 'Start') {
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
	genMACList2Set(20);
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
	my %test_data = $redis_con->hgetall('test_43807182c198');
	
	$RAD_REQUEST{'Alc-Subsc-ID'} = $test_data{'Alc-Subsc-ID'};
	$RAD_REQUEST{'NAS-IP-Address'} = $test_data{'NAS-IP-Address'};
	$RAD_REQUEST{'Framed-IP-Address'} = $test_data{'Framed-IP-Address'};
	$RAD_REQUEST{'Alc-SLA-Prof-Str'} = $test_data{'Alc-SLA-Prof-Str'};
	$RAD_REQUEST{'Alc-Subsc-Prof-Str'} = $test_data{'Alc-Subsc-Prof-Str'};
	$RAD_REQUEST{'ADSL-Agent-Circuit-Id'} = $test_data{'ADSL-Agent-Circuit-Id'};
	$RAD_REQUEST{'Acct-Start-Time'} = $test_data{'Acct-Start-Time'};
	$RAD_REQUEST{'Acct-Session-Id'} = $test_data{'Acct-Session-Id'};
	$RAD_REQUEST{'NAS-Port'} = $test_data{'NAS-Port'};
	$RAD_REQUEST{'NAS-Port-Id'} = $test_data{'NAS-Port-Id'};
	$RAD_REQUEST{'Acct-Status-Type'} = $test_data{'Acct-Status-Type'};
	$RAD_REQUEST{'Calling-Station-Id'} = $redis_con->srandmember('rand_mac_list');
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

sub setSubscHash {
	return 0 if @_ != 1;
	my $key = $_[0];
	eval {
		# do something risky...
		foreach my $attr ( keys %{$aluEnv{'CachedAVP'}}) {
			my $ret = $redis_con->hset($key, $attr => $RAD_REQUEST{$attr});
			#print "add $attr ok." if $ret == 1;
			print "add $attr fail." if $ret != 1;
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

###### For Test #######
my %RAD_REQUEST;
my %RAD_CHECK;
#die "INPUT: -r[random MAC]|KEY|MAC[must give without -r]|Acct-Status-Type\n" if scalar @ARGV < 3;
radiusSimulation();
#######################

=setUpRedisConn
=END
