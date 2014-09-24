#!/usr/bin/perl

use strict;
use warnings;
use Redis;
use vars qw(%RAD_REQUEST %RAD_CHECK)

my $redis_con;

sub setUpRedisConn {
	$redis_con = Redis->new(
		sever => 127.0.0.1,
		reconnect => 3,	
	);
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

sub main {
	setUpRedisConn();
	my $key = '168.95.179.11';
	testFlow($key);

	delSet($key);
}

main();