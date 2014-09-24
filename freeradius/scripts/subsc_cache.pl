use strict;
use warnings;
use vars qw(%RAD_REQUEST %RAD_CHECK);
use Redis;
use Config::Std { def_sep => '=' };
#use lib '/home/okis/perl5/lib/perl5';
use Log::Lite;

use constant RLM_MODULE_REJECT	=>	0;
use constant RLM_MODULE_OK	=>		2;
use constant RLM_MODULE_NOOP	=>	7;
use constant RLM_MODULE_UPDATED	=>	8;

my $logpath = '';
my $redis_con;
setUpRedisConn();

sub accounting {
	my $acct_status = $RAD_REQUEST{'Acct-Status-Type'};
	my $key = $RAD_REQUEST{'NAS-IP-Address'};
	my $umac = $RAD_REQUEST{'Calling-Station-Id'};

	if ($acct_status eq 'Start') {
		# Caching pre-auth subscriber information from Accounting packet to set in redis server.
		if(isMemberExist($key,$umac) != 1){
			addSubsc2Set($key,$umac);
		}
		return RLM_MODULE_OK;
	} elsif ($acct_status eq 'Stop') {
		# Clearing cached subscriber information from set in redis server.
		removeMemFromSet($key,$umac);
		return RLM_MODULE_OK;
	} else {
		# Do not process other types of Accounting.
		return RLM_MODULE_NOOP;
	}
}

sub setUpRedisConn {
	eval {
		# try to get a connection from Redis server.
		$redis_con = Redis->new(
			sever => 127.0.0.1,
			reconnect => 3,	
		);
	};
	if ($@) {
		# handle failure...
	}
	
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
	die "Too many arguments." if @_ > 1;
	$sep = '' if !defined($_[0]);
	my @chars = ('a'..'f','0'..'9');
	my $mac = '';
	for(my $i=1;$i<=6;$i++){
		my $seg = '';
		foreach(1..2){
			my $a = $chars[rand(@chars)];
			my $b = $chars[rand(@chars)];
			$seg = "$a$b";
		}
		$mac .= $seg if $i==1;
		$mac .= "$sep$seg" if $i>1;
	}
	return $mac;
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

sub delSet {
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

=setUpRedisConn
=END
