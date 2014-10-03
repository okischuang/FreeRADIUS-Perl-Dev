#!/usr/bin/perl
############################################################################
# This script creates a socket server for test LI function
############################################################################

use strict;
use warnings;
use IO::Socket::INET;

# flush after every write
$| = 1;

my ($socket,$received_data,$key);
my ($peeraddress,$peerport);
$key ='alualu';
$socket = new IO::Socket::INET (
			LocalPort => '3799',
			Proto => 'udp',
		) or die "ERROR in Socket Creation : $!\n";
	
if($socket){
	print "UDP Socket Set Up Successfully. I'm CoA Server NOW.";	
}
while(1)
{
	#print "\nSleeping 5 seconds to wait socket opening...\n";
        #sleep 5;
	#print "\nSocket Server is opening...\n";
	eval{
		# read operation on the socket
		#print "\nServer Sleeps for 5 seconds\n";
		#sleep 15;
		#print "\nServer wakes up!\n";
		$socket -> recv($received_data,1024);
		1;
	};
	print "Received Data Length:".length($received_data);	
	#next if $@;
	#chomp($received_data = localtime);

	# 
	$peeraddress = $socket->peerhost();
	$peerport = $socket->peerport();
	my $decodeData = &parameterDecode($received_data,$key);
	print "\n($peeraddress, $peerport) said : $decodeData \n";
	
	my $isLI = '0';
	if($decodeData =~ /(.+)&username=(.+)/){
		if($2 eq '85211046' || '0919916043'){
			$isLI = '1';
		}
	}
	eval{
		my $send_data = "$key?&ret=$isLI";
		my $encodeData = &parameterEncode($send_data,$key);
		print "\nPrepared encodeData: $encodeData\n";
		print "\nServer Sleeps for 5 seconds\n";
		sleep 5;
		print "\nServer wakes up!\n";
		$socket->send($encodeData);
		1;
	};

}

#$socket->close();	

sub parameterDecode{
        my $str = $_[0];
        my $sec = $_[1];
        my ($i, $str_len, $len, $real_sec_key,$ret);

        $str = substr($str, 5);
        $len = length($str);
        $real_sec_key = $len.$sec;
        $str_len = length($real_sec_key);

        my @parm_array = split(//,$str);
        my @real_sec_key_array = split(//,"$real_sec_key");
        my @pass_parm;

        for ($i=0; $i<$len; $i++){
                push(@pass_parm, $parm_array[$i]^$real_sec_key_array[$i%$str_len]);
        }

        $ret = "";
        for (my $j=0; $j<scalar @pass_parm;$j++){
                $ret = $ret.$pass_parm[$j];
        }
        return $ret;
}


sub parameterEncode{
        my $str = $_[0];
        my $sec = $_[1];

        print "para 1: $str, para 2: $sec\n";
        my ($i, $str_len, $len, $real_sec_key);
        my @parm_array = split(//,$str);
        #&printCHAR(@parm_array);

        $len = length($str);
        print "String length is: $len\n";

        $real_sec_key = $len.$sec;
        print "Real Secret: $real_sec_key\n";

        $str_len = length($real_sec_key);
        print "Length of real secret: $str_len\n";

        my @real_sec_key_array = split(//,"$real_sec_key");
        #&printCHAR(@real_sec_key_array);

        my @pass_parm;

        for ($i=0; $i<$len; $i++){
                #print "parm_array $i: $parm_array[$i]\n";
                #print "real sec key $i:  $real_sec_key_array[$i%$str_len]\n";
                #$pass_parm[$i] = pack("u",$parm_array[$i]) ^ pack("u",$real_sec_key_array[$i%$str_len]);
                push(@pass_parm, $parm_array[$i]^$real_sec_key_array[$i%$str_len]);
                #$pass_parm[$i] = $tempXOR;
                #print "xor: $tempXOR \n";
                #print "pass_parm: $pass_parm[$i]\n";
        }
        my $countOfCypher = length(scalar @pass_parm);
        my $cypherHeader = scalar @pass_parm;
        print "countOfCypher: $countOfCypher\n";
        for (my $j=0; $j<(5-$countOfCypher);$j++){
                $cypherHeader = "0".$cypherHeader;
        }
        print "cypherHeader: $cypherHeader";
        my $ret = $cypherHeader.convertChar2Str(@pass_parm);
        print "\nTotal Length Of Crypted String:".length($ret);
        return $ret;
}

sub printCHAR{
        my @charArray = $_[0];

        foreach my $char (@charArray){
                print "$char. \n";
        }
}

sub convertChar2Str{
        my @charArray = @_;
        my $string = "";
        foreach my $char (@charArray){
                $string = $string.$char;
        }
        print "\n convertChar2Str: $string";
        print "\n convertChar2Str Length:".length($string);
        return $string;
}
