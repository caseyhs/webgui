package WebGUI::Macro::a_account;

#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2003 Plain Black LLC.
#-------------------------------------------------------------------
# Please read the legal notices (docs/legal.txt) and the license
# (docs/license.txt) that came with this distribution before using
# this software.
#-------------------------------------------------------------------
# http://www.plainblack.com                     info@plainblack.com
#-------------------------------------------------------------------

use strict;
use WebGUI::International;
use WebGUI::Macro;
use WebGUI::Session;
use WebGUI::URL;

#-------------------------------------------------------------------
sub process {
	my (@param, $temp);
        @param = WebGUI::Macro::getParams($_[0]);
	$temp = WebGUI::URL::page('op=displayAccount');
	if ($param[0] ne "linkonly") {
        	$temp = '<a class="myAccountLink" href="'.$temp.'">';
        	if ($param[0] ne "") {
        		$temp .= $param[0];
        	} else {
                	$temp .= WebGUI::International::get(46);
        	}
        	$temp .= '</a>';
	}
	return $temp;
}


1;


