###############################################################################
##                                                                           ##
##               Module for reading device-permission file                   ##
##                                                                           ##
##---------------------------------------------------------------------------##
## Author:    Ulrich Becker                                                  ##
## File:      dev_permissions.sh                                             ##
## Used from: iwrite.sh, iread.sh, iparted.sh, cross-chroot.sh               ##
## Date:      12.01.2014                                                     ##
## Revision:                                                                 ##
###############################################################################
#  Copyright 2014 INKATRON                                                    #
#                                                                             #
#  This module is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by       #
#  the Free Software Foundation, either version 3 of the License, or          #
#  (at your option) any later version.                                        #
#                                                                             #
#  This module is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of             #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              #
#  GNU General Public License for more details.                               #
#                                                                             #
#  You should have received a copy of the GNU General Public License          #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.      #
#                                                                             #
#  Dieses Modul ist Freie Software: Sie können es unter den Bedingungen       #
#  der GNU General Public License, wie von der Free Software Foundation,      #
#  Version 3 der Lizenz oder (nach Ihrer Wahl) jeder neueren                  #
#  veröffentlichten Version, weiterverbreiten und/oder modifizieren.          #
#                                                                             #
#  Dieses Modul wird in der Hoffnung, dass es nützlich sein wird, aber        #
#  OHNE JEDE GEWÄHRLEISTUNG, bereitgestellt; sogar ohne die implizite         #
#  Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR EINEN BESTIMMTEN ZWECK. #
#  Siehe die GNU General Public License für weitere Details.                  #
#                                                                             #
#  Sie sollten eine Kopie der GNU General Public License zusammen mit diesem  #
#  Programm erhalten haben. Wenn nicht, siehe <http://www.gnu.org/licenses/>. #
###############################################################################
# $Id: dev_permissions.sh,v 1.26 2015/01/30 18:39:36 uli Exp $

PREMISSION_FILE="/etc/dev_permissions.conf"
DEVICE_PREFIX="/dev/sd"

BYTES_PER_SECTOR=512

ERROR=""
INFO=""

if [ ! -f "$PREMISSION_FILE" ] && [ ! -n "$PERMISSION_FILE_NOT_MISSED" ]
then
   echo "ERROR: Missing \"$PREMISSION_FILE\"" 1>&2
   exit 1
fi

#----------------------------------------------------------------------------------------
#TODO Simplify it by "$(pidof -x $scriptname )"
isRunning()
{
   local thisPid=$1
   shift
   local thisProc="$(basename "$(readlink -m "$1")")"
   shift

   while [ "${1:0:1}" = "-" ]
   do
      shift  # Skipping options of own process
   done

   local shName="$(basename "$(readlink -m "$SHELL")")"
   local pidList=""
   local pid
   for pid in $(ls "/proc")
   do
      local procDir="/proc/$pid"
      [ -d "$procDir" ] || continue
      [ "$pid" = "$thisPid" ] && continue  # Skip this process it's self.
      [ "$(basename "$(readlink -f "${procDir}/exe")")" != "$shName" ] && continue  # Skip if it's not a shell
      local ppid=$(cat "${procDir}/stat" 2>/dev/null | awk {'printf($4)'})
      [ "$ppid" = "$thisPid" ] && continue # Skip a child process of its self.
      if [ "$(basename "$(readlink -f "/proc/${ppid}/exe")")" = "$shName" ]
      then # Skip a child process of a foreign process
         local pScriptName=$(cat -v "/proc/${ppid}/cmdline" 2>/dev/null | awk -F '@' {'printf($2)'} | tr -d '^' )
         [ -n "$pScriptName" ] && [ "$(basename "$(readlink -m "$pScriptName")")" = "$thisProc" ] && continue
      fi

      local param="${*} "
      local cmdLine=$(cat -v "${procDir}/cmdline" 2>/dev/null | tr -d '^' | tr '@' ' ')
      local n=0
      local j
      for j in $cmdLine
      do
         ((n++))
         [ -L "$j" ] && j="$(readlink -m "$j")"
         case $n in
            1)
               continue
            ;;
            2)
               [ "${j:0:1}" != "-" ] && [ "$(basename "$j")" != "$thisProc" ] && break
               if [ ! -n "${param%% *}" ]
               then
                  pidList="${pidList}${pid} "
                  break
               fi
            ;;
            *)
               [ "${j:0:1}" = "-" ] && continue # Skipping options of the recovered process
               local thisParam="${param%% *}"
               [ -L "$thisParam" ] && thisParam="$(readlink -m "$thisParam")"
               [ "$thisParam" = "$j" ] || break
               param=${param#* }
            ;;
         esac
         [ -n "${param%% *}" ] || pidList="${pidList}${pid} "
      done
   done
   echo "$pidList"
}


#------------------------------------------------------------------------------
isPresent()
{
   [ -n "$(which $1 2>/dev/null)" ] && echo true || echo false
}

#------------------------------------------------------------------------------
toHuman()
{
   local size="$1"
   local lastSize
   local base

   [ ! -n "$2" ] && base=1000.0 || base=$2

   local exponent=0
   while [ -n "${size%.*}" ]
   do
     ((exponent++))
     lastSize=$size
     size="$(echo "$size / $base" | bc -l)"
   done
   size="$(echo "scale=3; $lastSize / 1" | bc)"

   local unit
   case $exponent in
      1) unit="B" ;;
      2) unit="KB" ;;
      3) unit="MB" ;; # 8-)
      4) unit="GB" ;; # :-)
      5) unit="TB" ;; # ;-)
      6) unit="PB" ;; # >:-O
      *) unit="?" ;;  # :-(
   esac

   echo "$size $unit"
}

#-------------------------------------------------------------------------------
getFileSize()
{  #Get the size in bytes of possibly unmounted blockdevices too.
#   local LANG=C
#   local size=$(fdisk -lu "$1" 2>/dev/null | awk -F 'B, ' '{print ($2)}' | awk '{print ($1)}')
   local size=$(blockdev --getsize64 "$1")
   if [ "$?" != "0" ] || [ ! -n "$size" ]
   then
      size=$(stat $(readlink -m "$1") 2>/dev/null | grep "Size" | awk -F ': ' '{print ($2)}' | awk '{print ($1)}')
      [ "$?" != "0" ] && size=0
   fi
   echo $size
}

#------------------------------------------------------------------------------
getHighestSector()
{
   local lastSector=0
   local LANG=C
   local list=$(fdisk -lu "$1" 2>/dev/null | grep "${1}[0-9]" | tr -d '*' )

   if [ ! -n "$list" ]
   then
      echo $lastSector
      return 0
   fi

   local i
   local IFS=$'\n'
   for i in $list
   do
      local partSector=$(echo "$i" | awk '{print $3}')
      [ "$partSector" -gt "$lastSector" ] && lastSector=$partSector
   done

   echo $lastSector
}

#------------------------------------------------------------------------------
getSizeViaPartitions()
{
   local sectors=$(getHighestSector "$1")
   [ "$sectors" -gt "0" ] && echo $((($sectors + 1) * $BYTES_PER_SECTOR))
}


#------------------------------------------------------------------------------
listPermissions()
{
   if [ ! -s "$PREMISSION_FILE" ]
   then
      echo "ERROR: Permission-list \"${PREMISSION_FILE}\" not found or invalid!" 1>&2
      return 1
   fi

   local i
   local IFS=$'\n'
   for i in $( cat $PREMISSION_FILE )
   do
      unset IFS
      i=${i%%\#*}
      i=${i%%' '*}
      if [ -n "$i" ]
      then
         if $DO_VERBOSE
         then
            echo "File: \"${i}\", or last letter: \"${i##$DEVICE_PREFIX}\""
         else
            echo $i
         fi
      fi
   done
}

#------------------------------------------------------------------------------
getPermissions()
{
   local i
   local IFS=$'\n'
   for i in $( cat $PREMISSION_FILE )
   do
      unset IFS
      i=${i%%\#*}
      i=${i%%' '*}
      [ -n "$i" ] && echo $i
   done
}

#------------------------------------------------------------------------------
isPermitted()
{
   ERROR=""
   INFO=""

   if [ ! -s "$PREMISSION_FILE" ]
   then
      ERROR="\"$PREMISSION_FILE\" not found or invalid!"
      echo false
      return 1
   fi

   local device="$(readlink -m "$1")"

   local i
   local IFS=$'\n'
   for i in $(cat $PREMISSION_FILE 2>/dev/null )
   do
      unset IFS
      i=${i%%\#*}
      i=${i%%' '*}
      if [ -n "$i" ] && [ "$i" = "$device" ]
      then
         echo true
         return 0
      fi
   done
   echo false
   return 0
}

#------------------------------------------------------------------------------
getBlockDeviceName()
{
   if [ "${#1}" = "1" ]
   then
      echo "${DEVICE_PREFIX}${1}"
   else
      echo "${1}"
   fi
}

#------------------------------------------------------------------------------
checkPermissions()
{
   PERMITTED_DEVICE=$(getBlockDeviceName "$1")

   local res=$(isPermitted $PERMITTED_DEVICE)
   if [ -n "$ERROR" ]
   then
      echo "ERROR: $ERROR" 1>&2
      PERMITTED_DEVICE=""
      return 1
   fi

   if ! $res
   then
      echo "ERROR: $DEVICE_TEXT \"${PERMITTED_DEVICE}\" is not permitted!" 1>&2
      echo "Permitted devices:" 1>&2
      listPermissions 1>&2
      PERMITED_DEVICE=""
      return 1
   fi

   if [ ! -e $PERMITTED_DEVICE ]
   then
      echo "ERROR: $DEVICE_TEXT \"${PERMITTED_DEVICE}\" not found!" 1>&2
      PERMITTED_DEVICE=""
      return 1
   fi
}

#------------------------------------------------------------------------------
#getAllConnectedStorageDevices()
#{
#   sed -ne "s/.*\([sh]d[a-zA-Z]\+$\)/\/dev\/\1/p" "/proc/partitions"
#}

#------------------------------------------------------------------------------
#isStorageDeviceConnected()
#{
#   [ -n "$(getAllConnectedStorageDevices | grep "$1")" ]
#}

#------------------------------------------------------------------------------
getNumberOfFoundPermitedAppropriateDevices()
{
   local n=0
   local i
   local IFS=$'\n'
   for i in $(getPermissions)
   do
      unset IFS
      local size="$(getFileSize $i 2>/dev/null)"
      [ "$size" \> "0" ] && ( [ ! -n "$1" ] || [ "$size" -ge "$1" ] ) && ((n++))
   done
   echo $n
}

#------------------------------------------------------------------------------
listFuondPermitedDevices()
{
   if [ "$(getNumberOfFoundPermitedAppropriateDevices "$1" )" = "0" ]
   then
      echo "No connected device found!"
   else
      local i
      local IFS=$'\n'
      for i in $(getPermissions 2>/dev/null)
      do
         unset IFS
         local size=$(getFileSize $i)
         [ "$size" \> "0" ] && ( [ ! -n "$1" ] || [ "$size" -ge "$1" ] ) && echo "$i   Size: $(toHuman $size)"
      done
   fi
   return 0
}


#------------------------------------------------------------------------------
unmountMemoryDevice()
{
   local WAS_MOUNTED=false

   for i in $(df | grep "$1*")
   do
      case $i in
         $1[0-9] | $1)
            if [ -n "$(df | grep "$i")" ]
            then
               $DO_VERBOSE && echo "umount $i"
               umount $i
               local ret=$?
               if [ "$ret" != "0" ]
               then
                  echo "ERROR: Impossible to unmount partition: \"$i\"! Returncode: $RET" 1>&2
                  exit $ret
               fi
               WAS_MOUNTED=true
            fi
         ;;
      esac
   done

   if ! $WAS_MOUNTED && $DO_VERBOSE
   then
      echo "INFO: There was nothing to unmount on device: \"$1\"."
   fi
}

#=================================== EOF ======================================
