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

# define global hash variables for storing config
my %qos;

sub log_err {
	my $errMsg = $_[0];
	log("error","QoS_control","$errMsg");
}

sub setUpConfig {
	eval {
		# do something risky...
		read_config "$confpath/wispr_qos.cfg" => %qos;
	};
	if ($@) {
		# handle failure...
		log_err("$@");
	}
}

sub post_auth {
	&set_qos_for_lite_gw;
}

sub set_qos_for_lite_gw {

	# check if reading config file successfully
	if(%qos) {
		my $realm_section = $RAD_REQUEST{'FreeRADIUS-WiFi-Realm'};
		if($realm_section eq "") {
			if($RAD_REQUEST{'User-Name'} =~ /(.+)\/(.+)/) {
				$realm_section = $1;
			}
			elsif($RAD_REQUEST{'User-Name'} =~ /(.+)@(.+)/) {
				$realm_section = $2;
			}
			else{
				$realm_section = 'Default';
			}
		}	

		my $override = $qos{"$realm_section"}{override};
		my ($burst, $upRate, $downRate, $ito, $sto, $li_Dest);
		
		if($override eq 1){
			&radiusd::radlog(L_DBG, "Set --$realm_section-- QoS profile by config.\n");
			$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = $qos{"$realm_section"}{up}*1000;
			$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = $qos{"$realm_section"}{down}*1000;
			$RAD_REPLY{'Idle-Timeout'} = $qos{"$realm_section"}{ito};
			$RAD_REPLY{'Session-Timeout'} = $qos{"$realm_section"}{sto};
			if($qos{"$realm_section"}{url} ne '') {
				$RAD_REPLY{'WISPr-Redirection-URL'} = $qos{"$realm_section"}{url};
			}
		}
		else {
			
			# CHT Employee Profile
			if($RAD_REPLY{'WISPr-Bandwidth-Max-Up'} eq "0" || $RAD_REPLY{'WISPr-Bandwidth-Max-Down'} eq "0") {
				&radiusd::radlog(L_DBG, "Set Employee Profile.");
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = 200000000;
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = 100000000;
			}		
			if(!defined $RAD_REPLY{'WISPr-Bandwidth-Max-Up'} || !defined $RAD_REPLY{'WISPr-Bandwidth-Max-Down'}) {
				&radiusd::radlog(L_DBG, "Missing Rate Limit Qos value from AAA. Apply --Default-- profile.\n");
				$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = $qos{Default}{up}*1000;      
				$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = $qos{Default}{down}*1000;
			}

			if(!defined $RAD_REPLY{'Idle-Timeout'} || !defined $RAD_REPLY{'Session-Timeout'}) {
				&radiusd::radlog(L_DBG, "Missing Timeout Qos value from AAA. Apply --Default-- profile.\n");
				$RAD_REPLY{'Idle-Timeout'} = $qos{Default}{ito};
				$RAD_REPLY{'Session-Timeout'} = $qos{Default}{sto};
			}
			else {
				$ito = $RAD_REPLY{'Idle-Timeout'};
				$sto = $RAD_REPLY{'Session-Timeout'};
			}

		}
		return RLM_MODULE_UPDATED;
	}
	else{
		&radiusd::radlog(L_ERR, "Fail to read Config\n");
		$RAD_REPLY{'WISPr-Bandwidth-Max-Up'} = 20488000;
		$RAD_REPLY{'WISPr-Bandwidth-Max-Down'} = 5048000;
		$RAD_REPLY{'Idle-Timeout'} = 600;
		$RAD_REPLY{'Session-Timeout'} = 14400;
		return RLM_MODULE_OK;
	}
}


