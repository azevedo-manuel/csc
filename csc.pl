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
# Version 0.3 - 8.Apr.2015
#
# Change log:
# Version 0.1 - Initial version
# Version 0.2 - Cleanup, bug fixes
# Version 0.3 - Added additional Lync SRV records
#
# Command line switches:
#  -d    	Enable debug mode
#  -v    	Enable verbose mode. If absent, will only show active records
#  -h    	Help
#  -s srv	Test specific SRV record
#

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
	print " -v     Enable verbose mode. It will also list SRV records not found in DNS.\n";
	print " -h     This help text\n";
	print " -s srv Test a specific SRV record\n\n";
	print "If domain is absent, will try to use the host's domain\n\n";
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
			"_sip._tcp",
			"_sip._udp",
			"_sips._tcp",
			"_sips._tls",
			"_sip._tls",
			"_h323cs._tcp",
			"_h323ls._udp",
			"_h323rs._udp",
			"_cisco-uds._tcp",
			"_cuplogin._tcp",
			"_collab-edge._tls",
			"_sipinternaltls._tcp",
			"_sipinternal._tcp",
			"_sipfederationtls._tcp"
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
foreach my $srv (@srvRecords) {
	debugMsg("SRV record: ".$srv);
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