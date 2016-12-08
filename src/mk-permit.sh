#!/bin/bash
###############################################################################
##                                                                           ##
##    Generator for the I-Tools permission-File /etc/dev_permissions.conf    ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     mk-permit.sh                                                    ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     29.09.2014                                                      ##
## Revision:                                                                 ##
###############################################################################
#  Copyright 2014 INKATRON                                                    #
#                                                                             #
#  This program is free software: you can redistribute it and/or modify       #
#  it under the terms of the GNU General Public License as published by       #
#  the Free Software Foundation, either version 3 of the License, or          #
#  (at your option) any later version.                                        #
#                                                                             #
#  This program is distributed in the hope that it will be useful,            #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of             #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              #
#  GNU General Public License for more details.                               #
#                                                                             #
#  You should have received a copy of the GNU General Public License          #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.      #
#                                                                             #
#  Dieses Programm ist Freie Software: Sie können es unter den Bedingungen    #
#  der GNU General Public License, wie von der Free Software Foundation,      #
#  Version 3 der Lizenz oder (nach Ihrer Wahl) jeder neueren                  #
#  veröffentlichten Version, weiterverbreiten und/oder modifizieren.          #
#                                                                             #
#  Dieses Programm wird in der Hoffnung, dass es nützlich sein wird, aber     #
#  OHNE JEDE GEWÄHRLEISTUNG, bereitgestellt; sogar ohne die implizite         #
#  Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR EINEN BESTIMMTEN ZWECK. #
#  Siehe die GNU General Public License für weitere Details.                  #
#                                                                             #
#  Sie sollten eine Kopie der GNU General Public License zusammen mit diesem  #
#  Programm erhalten haben. Wenn nicht, siehe <http://www.gnu.org/licenses/>. #
###############################################################################
# $Id: mk-permit.sh,v 1.3 2015/01/21 10:41:33 uli Exp $

DO_VERBOSE=true

if [ $UID -ne 0 ]
then
   echo "Not allow, because you are not root!" 1>&2
   echo "Try: sudo ${0##*/} $ARGS"
   exit 1
fi

PATH="/sbin:$PATH"

PERMISSION_FILE_NOT_MISSED=true
PERMISSION_MODULE="${0%/*}/dev_permissions.sh"
source $PERMISSION_MODULE
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Module \"${PERMISSION_MODULE}\" not found!" 1>&2
   exit $RET
fi

clear
echo "Replace all external storage-devices (SD-card(s), USB-stick(s), CompactFlash(es), etc.)"
echo "from this computer if connected."
read -p "Press q to quit or any other key to continue: " I
if [ "$I" = "q" ]
then
   echo "Exit by user."
   exit 0
fi

BLOCK_DEVICES=""
DEVICELIST=$(ls ${DEVICE_PREFIX}[b-z] 2>/dev/null)
for i in $DEVICELIST
do
    [ $(getFileSize "$i") = 0  ] && BLOCK_DEVICES="${BLOCK_DEVICES}${i}\n"
done

if [ ! -n "$BLOCK_DEVICES" ]
then
   $DO_VERBOSE && echo "INFO: No unmounted devicenodes found."
   echo "Connect all external storage-devices (SD-card(s), USB-stick(s), CompactFlash(es), etc.)"
   echo "Press enter when they are connected."
   read
   echo "Wait..." 
   sleep 3
   [ -n "$DEVICELIST" ] || DEVICELIST="dummy"
   EXT_DEVICES=$(ls ${DEVICE_PREFIX}[b-z] 2>/dev/null | grep -v "$DEVICELIST")
   if [ ! -n "$EXT_DEVICES" ]
   then
      echo "ERROR: No externel storage-devices found!" 1>&2
      exit 1
   fi
   for i in $EXT_DEVICES
   do
      BLOCK_DEVICES="${BLOCK_DEVICES}${i}\n"
   done
fi

clear
echo "Devices with shall be permit for write-acesses:"
printf $BLOCK_DEVICES

if [ -f "$PREMISSION_FILE" ]
then
   DO_VERBOSE=false
   echo
   echo "WARNING: File \"$PREMISSION_FILE\" already exist by these permited devices:"
   listPermissions
   echo "Overwrite these block-devices by these devices?"
   printf $BLOCK_DEVICES
   read -p "Press y to overwrite it, quit is any ather key. " I
   if [ "$I" != "y" ]
   then
      echo "Exit by user"
      exit 0
   fi
fi

#PREMISSION_FILE=test.conf

cat << __EOF__  > $PREMISSION_FILE
###############################################################################
##                                                                           ##
##           List of the permitted block-devices for the I-Tools             ##
##                                                                           ##
###############################################################################
# File:         $PREMISSION_FILE
# Generated by: ${0##*/}
# Date:         $(date)
###############################################################################

# For the I-Tools permitted block-devices:
$(printf $BLOCK_DEVICES)

#==================================== EOF =====================================
__EOF__
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Unable to write file \"$PREMISSION_FILE\"! Return=$RET" 1>&2
   exit $RET
fi

echo
cat $PREMISSION_FILE
echo
echo "File \"$PREMISSION_FILE\" successful generated."
#=================================== EOF ======================================
