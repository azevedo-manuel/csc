#!/usr/bin/perl
# 
#
# collaboration SRV check - csc
# Copyright (C) 2015 Manuel Azevedo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ** Don't forget to install Net::DNS and Text::Table modules in Perl **
# 
# SRV sources:
# http://www.cisco.com/c/en/us/td/docs/voice_ip_comm/jabber/iPad/9_x/JABP_BK_J3C828CB_00_jabber-for-ipad-admin_chapter_01000.html
# http://wiki.xmpp.org/web/SRV_Records
# http://www.cisco.com/c/en/us/td/docs/voice_ip_comm/jabber/10_5/CJAB_BK_D6497E98_00_deployment-installation-guide-ciscojabber.pdf
# http://www.cisco.com/c/en/us/td/docs/solutions/CVD/Collaboration/enterprise/collbcvd/edge.html
# http://www.cisco.com/c/dam/en/us/td/docs/telepresence/infrastructure/vcs/config_guide/X8-1/Cisco-VCS-Basic-Configuration-Control-with-Expressway-Deployment-Guide-X8-1.pdf
# https://technet.microsoft.com/en-us/library/bb663700%28v=office.12%29.aspx
# http://www.cisco.com/c/en/us/td/docs/voice_ip_comm/cups/8_0/english/integration_notes/Federation/Federation/CUPConfig_chapter.pdf

#
# Change log:
# Version 0.1 - Initial version
# Version 0.2 - Clean-up, bug fixes
# Version 0.3 - Added additional Lync SRV records
# Version 1.0 - First release. Added version information. Added progress information. Clean-up
# Version 1.1 - Added additional SRV records. Added SRV records descriptions as comments.
#
# Command line switches:
#  -d    	Enable debug mode
#  -h    	Help
#  -s srv	Test specific SRV record
#  -v    	Enable verbose mode. If absent, will only show active records
#  -V    	Print version information


use constant version     => "1.1 - 9.Apr.2015";
use constant programName => "collaboration SRV check - csc";
use constant developer   => "Manuel Azevedo";
use strict;
use Getopt::Std;
use IO::Socket;
use Net::DNS;
use Net::Domain 'hostdomain';
use Text::Table;

#
# Sub-routine for printing debug messages
#
my $debug = 0;
sub debugMsg{
	if ($debug) {
		print "*DEBUG: ".$_[0]."\n";
	}
}

#
# Sub-routine for printing verbose messages
#
my $verbose =0;
sub verboseMsg{
	if ($verbose) {
		print $_[0]."\n";
	}
}

#
# Sub-routine for printing progress messages
#
sub progressMsg{
	print $_[0]."\r";
	$|=1;
}


#
# Command line options
# 's' is a parameter that has a field
#

my %Options;
getopt('s',\%Options);

#
# User used help switch. Print help.
# Exit without error
#
if ( $Options{h} ) {
	print "\nUsage: ";
	print $0." [-options] [domain]\n\n";
	print "where options are:\n";
	print " -d     Enable debug mode\n";
	print " -h     This help text\n";
	print " -s srv Test a specific SRV record\n";
	print " -v     Enable verbose mode. It will also list SRV records not found in DNS.\n";
	print " -V     Version information\n\n";
	print "If domain is absent, will try to use the host's domain\n\n";
	exit 0;
}

#
# Print version information.
# Exit without error
#
if ( $Options{V} ){
	print "\n";
	print "Application : ".programName."\n";
	print "Version     : ".version."\n";
	print "Copyright   : ".developer."\n\n";
	exit 0;
}

#
# Enable debug mode
#
if ( $Options{d} ) {
	$debug = 1;
	debugMsg("Debug enabled");
}

#
# Enable verbose mode
#
if ( $Options{v} ) {
	$verbose = 1;
	debugMsg("Verbose enabled");
}

#
# If user provides a SRV record, use it.
# Unless, use the built-in SRV array
#
my @srvRecords;
if ( $Options{s} ) {
	@srvRecords = ($Options{s});
	debugMsg("Specific SRV record search");
	verboseMsg("Using '".$Options{s}."' SRV record");
} else {
	debugMsg("Generic SRV record search");
	verboseMsg("Using the default Cisco SRV records"); 
	@srvRecords = ( 
			"_sip._tcp",					# SIP TCP
			"_sip._udp",					# SIP UDP
			"_sips._tcp",					# Secure SIP TCP
			"_sips._tls",					# Secure SIP TLS
			"_sip._tls",					# SIP TLS
			"_h323cs._tcp",					# H.323 Call signaling
			"_h323ls._udp",					# H.323 Location service
			"_h323rs._udp",					# H.323 Registration service
			"_cisco-uds._tcp",				# Cisco Unified Communications Manager
			"_cuplogin._tcp",				# Cisco Unified Presence
			"_collab-edge._tls",			# Cisco VCS Expressway-E
			"_sipinternaltls._tcp",			# Microsoft Lync SIP TLS for internal registrations
			"_sipinternal._tcp",			# Microsoft Lync SIP for internal registrations
			"_sipfederationtls._tcp",		# Cisco and Lync SIP TLS federation
			"_xmpp-client._tcp",			# XMPP, Cisco WebEx Messenger
			"_xmpp-server._tcp",			# XMPP
			"_cisco-phone-tftp._tcp",		# Cisco Unified Communications Manager TFTP
			"_cisco-phone-http._tcp ",		# Cisco Unified Communications Manager CCMIP
			"_sip._tcp.internal",			# Cisco TelePresence Video Communication Server (Internal)
			"_sip._tcp.external",			# Cisco TelePresence Video Communication Server (External)
			"_ciscowtp._tcp",				# Cisco Jabber Video for TelePresence
			"_ciscowtp._tcp",				# Cisco WebEx TelePresence
			"_turn._tcp",					# TURN TCP
			"_turn._udp",					# TURN UDP
			"_turns._tcp",					# TURNS TCP
			"_stun._tcp",					# STUN TCP
			"_stun._udp",					# STUN UDP
			"_stuns._tcp",					# STUNS TCP
			"_gc._msdcs._tcp",				# Active Directory Global Catalog
			"_ldap._msdcs._tcp",			# Active Directory LDAP Directories
	);
}

#
# If not provided, it will try to use the host's domain.
# If user provides a domain in the command it will use it 
# If domain cannot be discovered nor given, exit with error
#
my $domain = shift;
if ( $domain ) {
	debugMsg("Domain given.");
	verboseMsg("Using '".$domain."' domain"); 
} else {
	debugMsg("No domain given. Trying to guess host domain");
	if ( hostdomain ne "" ){
		$domain=hostdomain;
		debugMsg("Found hostdomain. Trying");
		verboseMsg("Using host's own '".$domain."' domain");
	} else {
		print "ERROR: Missing domain. No domain to test\n";
		exit 1;
	}
}

#
# Create a table for data presentation
#
my $table = Text::Table -> new (
	{ is_sep =>1, title => "|", body => "|" },"SRV record", 
	{ is_sep =>1, title => "|", body => "|" },"Target", 
	{ is_sep =>1, title => "|", body => "|" },"Priority", 
	{ is_sep =>1, title => "|", body => "|" },"Weight", 
	{ is_sep =>1, title => "|", body => "|" },"Port",
	{ is_sep =>1, title => "|", body => "|" },"SRV Found",
	{ is_sep =>1, title => "|", body => "|" },"TCP Open",
	{ is_sep =>1, title => "|", body => "|" }
);

#
# Go through SRV list, get SRV record and test if open
#
my $tcpOpen;
my $totalRecords=scalar @srvRecords;
my $i=0;
foreach my $srv (@srvRecords) {
	debugMsg("SRV record: ".$srv);
	$i++;
	progressMsg("Retrieving SRV records: ".int(($i/$totalRecords)*100)."%");
	my $res   = Net::DNS::Resolver->new;
	my $reply = $res->query($srv.".".$domain,"SRV");
	if ($reply) {
		debugMsg("SRV record answer from DNS");
		#
		# Each SRV answer can have more than one host in the record.
		# Go through each one of them
		#
		foreach my $rr ($reply->answer) {
			#
			# If the SRV includes TCP or TLS, test if TCP port is open
			#
			if  ( (index($srv,"tcp") > 0) || (index($srv,"tls") > 0)  ) {
				debugMsg("SRV record is a TCP record. Test if TCP is open");
				my $socket = IO::Socket::INET->new(PeerAddr => $rr->target, PeerPort => $rr->port, Proto => 'tcp', Timeout => 1);
				if ($socket) {
					debugMsg("Port open");
					$tcpOpen = "Yes";
				} else {
					debugMsg("Port not open");
					$tcpOpen = "No";
				}
			}
			#
			# UDP SRV records cannot be checked, so status is N/A
			#
			else {
				debugMsg("SRV record is not a TCP record. There is no Port status to test");
				$tcpOpen = "N/A";
			}
			#
			# Add the record to the table
			#
			$table->add($srv,$rr->target,$rr->priority,$rr->weight,$rr->port,"Yes",$tcpOpen);
		}
	} else {
		#
		# Only if verbose mode is enabled, add the unavailable records to the table
		#
		debugMsg("SRV record not answered from DNS. Assume not available");
		if ( $verbose ) {
			$table->add($srv,"","","","","No","");
		}
	}
}

#
# Print the table
#

print $table->rule('-','+');
print $table->title;
print $table->rule('-','+');
print $table->body;
print $table->rule('-','+');
exit 0;