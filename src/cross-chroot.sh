#!/bin/bash
###############################################################################
##                                                                           ##
##                           Cross-Changeroot                                ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     cross-chroot.sh                                                 ##
## Require:  dev_permissions.sh, imount.sh                                   ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     06.05.2014                                                      ##
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
# $Id: cross-chroot.sh,v 1.42 2014/10/16 17:24:14 uli Exp $
VERSION=0.30
DO_DEBUG=false
#DO_DEBUG=true

PROG_NAME=${0##*/}
DO_VERBOSE=false
DO_MOUNT_HOST_FS=false
DO_MOUNT_FSTAB_ITEMS=false
DO_FORCE_EMULATOR_COPY=false
DO_LIST_PERMITTED_BLOCK_DEVICES=false
DO_PRINT_HELP=false
DO_PRINT_VERSION=false
DO_USE_X11=false

DEFAULT_TARGET_PROGRAM="sh"

TEST_FILE="/sbin/init"

DEFAULT_UNMOUNT_OPTION=""

IMOUNT_OPTIONS=""
IMAGE_MOUNTER="${0%/*}/imount.sh"

PERMISSION_MODULE="${0%/*}/dev_permissions.sh"
source $PERMISSION_MODULE
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Module \"${PERMISSION_MODULE}\" not found!" 1>&2
   exit $RET
fi

IS_EMULATOR_COPIED=false

DEFAULT_MOUNTPOINT="/mnt"
DEFAULT_MOUNTLIST="/dev:/dev/pts:/dev/shm:/proc:/sys"
X11_MOUNT="/tmp"
TO_MOUNT=""
IS_MOUNTED=""

X_AUTHORITY_FILE=".Xauthority"


DISABLE_EXT=".disabled"
DEFAULT_DESABLE_LIST="/etc/ld.so.preload"
TO_DISABLE=$DEFAULT_DESABLE_LIST
IS_DISABLED=""

DEVICE_FILE_NAME=""
IMAGE_FILE_NAME=""
MOUNTPOINT=""
NEW_ROOT=""
ENTER_EXEC=""
LEAVE_EXEC=""

PATH="/sbin:$PATH"

#------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

$(basename $(readlink -m $PROG_NAME)): (C) 2014 www.INKATRON.de
Author: Ulrich Becker
Version: $VERSION

Usage: $PROG_NAME [OPTION] <target-root> [COMMAND [ARG]...]

<target-root> can be a path, a image-file or a block-device
If no command is given, run "${SHELL} -i" (default: "/bin/sh -i").

Block-devices are checked in "$PREMISSION_FILE"

Options:
   -h, --help   This help
   -v           Verbose
   -l           List permitted block-devices
   -f           Try to mount items of <target-root>/etc/fstab if found.
   -m           Mount "$DEFAULT_MOUNTLIST" to target-root
   -m=<mount1[:mount2[...:mountX]]> Explicit mount-list.
   -m+<mount1[:mount2[...:mountX]]> Additional explicit mount-list to the default "$DEFAULT_MOUNTLIST".
   -p=<mountpoint> Mountpoint for image-files or block-devices
                   default is: "/mnt".

   --enter=<enter-program>
   --leave=<leave-program>

   --version   Version-number

__EOH__
}

#------------------------------------------------------------------------------
hasRootFilesystem()
{
   local mustHave="bin dev etc lib proc sbin sys tmp usr var"

   local has=$(ls $1)
   local i
   for i in $mustHave
   do
      local found=false
      local j
      for j in $has
      do
         if [ "$i" = "$j" ]
         then
            found=true
            break
         fi
      done
      if ! $found
      then
         echo false
         return
      fi
   done
   echo true
}

#------------------------------------------------------------------------------
reEnableFiles()
{
   local targetRoot=$1

   local i
   for i in $IS_DISABLED
   do
      if [ -w "${targetRoot}${i}${DISABLE_EXT}" ]
      then
         $DO_VERBOSE && echo "INFO: Reenable \"${targetRoot}${i}${DISABLE_EXT}\" to \"${targetRoot}${i}\"."
         mv ${targetRoot}${i}${DISABLE_EXT} ${targetRoot}${i}
         local ret=$?
         [ "$ret" != "0" ] && echo "ERROR: Unable to rename \"${targetRoot}${i}${DISABLE_EXT}\" in \"${targetRoot}${i}\"! return: $ret" 1>&2
      fi
   done
}

#------------------------------------------------------------------------------
disableFiles()
{
   local targetRoot=$1

   local i
   local IFS=:
   for i in $TO_DISABLE
   do
      if [ -w "${targetRoot}${i}" ]
      then
         $DO_VERBOSE && echo "INFO: Disabele \"${targetRoot}${i}\" to \"${targetRoot}${i}${DISABLE_EXT}\"."
         mv ${targetRoot}${i} ${targetRoot}${i}${DISABLE_EXT}
         local ret=$?
         if [ "$ret" != "0" ]
         then
            echo "ERROR: Unable to rename \"${targetRoot}${i}\" in \"${targetRoot}${i}${DISABLE_EXT}\"! return: $ret" 1>&2
            unset IFS
            return $ret
         fi
         IS_DISABLED="${IS_DISABLED} ${i}"
      elif [ -w "${targetRoot}${i}${DISABLE_EXT}" ]
      then
         echo "WARNING: \"${targetRoot}${i}\" already disabled!"
         IS_DISABLED="${IS_DISABLED} ${i}"
      fi
   done
   return 0
}

#------------------------------------------------------------------------------
unmountPartitions()
{
   if [ -n "$IMAGE_FILE_NAME" ]
   then
      if $DO_VERBOSE
      then
         local imountOption="-vU"
      else
         local imountOption="-U"
      fi
      $IMAGE_MOUNTER $imountOption $IMAGE_FILE_NAME
   fi
}

#------------------------------------------------------------------------------
sysUnmount()
{
   local targetRoot=$1

   local i
   local IFS=' '
   for i in $IS_MOUNTED
   do
      local mountpoint="${targetRoot}${i}"
      local umountCount=1
      local umountOption=$DEFAULT_UNMOUNT_OPTION
      local ret=-1
      while [ "$ret" != "0" ]
      do
         $DO_VERBOSE && echo "INFO: Unmount \"${mountpoint}\" by option: \"${umountOption}\"."
         umount ${umountOption} "${mountpoint}"
         ret=$?
         if [ "$ret" != "0" ]
         then
            ((umountCount++))
            echo "ERROR: Impossible to unmount \"${mountpoint}\"! Returncode: $ret" 1>&2
            echo "       Some of the devicefiles in \"${mountpoint}\" are possibly still used:" 1>&2
            echo "       $(fuser -a "${mountpoint}")" 1>&2
            read -p "Retry $umountCount ? Type \"y\", by option -l type \"l\", by option -f type \"f\", fuser -k type \"k\": " ANSWER
            case $ANSWER in
               "y")
                  option=$DEFAULT_UNMOUNT_OPTION
               ;;
               "l"|"f")
                  option="-${ANSWER}"
               ;;
               "k")
                  $DO_VERBOSE && echo "INFO: \"Run fuser -ki ${mountpoint}\""
                  echo "y" | fuser -ki "${mountpoint}"
                  sleep 1
                  umountOption=$DEFAULT_UNMOUNT_OPTION
               ;;
               *)
                  ret="0"
               ;;
            esac
         fi
      done
   done
   unset IFS
}

#------------------------------------------------------------------------------
isBootPartition()
{
   # TODO Check wether part1 is always the boot-partition!
   if [ "${1##*[!0-9]}" = "1" ]
   then
      echo true
   else
      echo false
   fi
}

#------------------------------------------------------------------------------
mountFstabItems()
{
   local partitionTable="$1"
   local targetRoot="$2"
   local fsTabFile="${targetRoot}/etc/fstab"
   local patternDev="/dev/"
   local patternBoot="boot"

   if [ ! -s "$fsTabFile" ]
   then
      echo "ERROR: Filesystem-table \"$fsTabFile\" invalid or not found!" 1>&2
      return 1
   fi

   $DO_VERBOSE && echo "INFO: Reading filesystem-table in: \"$fsTabFile\""
   local fstab=$(cat $fsTabFile)
   local ret=$?
   if [ "$ret" != "0" ]
   then
      echo "ERROR: Could not read \"$fsTabFile\"! Return = $ret" 1>&2
      return $ret
   fi

   local i
   local rootDriveName=""
   local lastDriveName=""
   local noDifferencePhysicalDrives=true

   local line=0
   local IFS=$'\n'
   for i in $fstab
   do
      unset IFS
      ((line++))
      $DO_DEBUG && echo "DBG: Line ${line}: $i"
      i=${i%%\#*}
      i=${i%' '*}
      [ -n "$i" ] || continue
      local driveName=$(echo "$i" | awk '{print $1}' | grep "$patternDev")
      [ -n "$driveName" ] || continue
      driveName=${driveName%%${driveName##*[!0-9]}}
      if [ "$(echo "$i" | awk '{print $2}' )" = "/" ]
      then
         if [ -n "$rootDriveName" ]
         then
            echo "ERROR: At line $line ambiguous mountpoint in \"$fsTabFile\" found!" 1>&2
            sysUnmount "$targetRoot"
            return 1
         fi
         rootDriveName="$driveName"
      fi
      if [ -n "$lastDriveName" ] && [ "$driveName" != "$lastDriveName" ]
      then
         noDifferencePhysicalDrives=false
      fi
      lastDriveName="$driveName"
   done

   if [ ! -n "$rootDriveName" ]
   then
      if $noDifferencePhysicalDrives
      then
         rootDriveName="$lastDriveName"
      else
         echo "WARNING: No unambiguous mountpoints in \"$fsTabFile\" found!"
      fi
   fi

   $DO_VERBOSE && echo "INFO: Reading $line lines of \"$fsTabFile\"."

   line=0
   local mounts=0
   local IFS=$'\n'
   for i in $fstab
   do
      unset IFS
      ((line++))
      i=${i%%\#*}
      i=${i%' '*}
      [ -n "$i" ] || continue
      local partNumber=""
      local driveName=$(echo "$i" | awk '{print $1}' | grep "$patternDev")
      if [ -n "$driveName" ]
      then
         $DO_DEBUG && echo "DBG: Drivename=$driveName"
         partNumber=${driveName##*[!0-9]}
         driveName=${driveName%%$partNumber}
         [ "$rootDriveName" = "$driveName" ] || continue   # If not the same physical drive, then continue.
      elif [ -n "$(echo "$i" | awk '{print $1}' | grep -i "$patternBoot")" ]
      then
         $DO_DEBUG && echo "DBG: ***Label***"
         driveName="$patternBoot"
      else
         continue
      fi

      local relMountpoint=$(echo "$i" | awk '{print $2}')
      [ "${relMountpoint:0:1}" = "/"  ] || continue # Mount directorys only.
      local absMountpoint="${targetRoot}${relMountpoint}"

      local j
      local IFS=$'\n'
      for j in $partitionTable
      do
         unset IFS
         [ "$j" = "$targetRoot"  ] && continue    # Mount of "/" will made by chroot.
         # Same physical drive and same partition-number or item is a boot-label?
         if [ "$partNumber" = "${j##*[!0-9]}" ] || ( [ "$driveName" = "$patternBoot" ] && $(isBootPartition "$j") )
         then
            if [ ! -d "$absMountpoint" ]
            then
               echo "ERROR: At line $line of \"$fsTabFile\": Mountpoint of item \"$i\" does not exist!" 1>&2
               sysUnmount "$targetRoot"
               return 1
            fi
            $DO_VERBOSE && echo "INFO: Mount item of \"$fsTabFile\" --> \"$j\" to \"$absMountpoint\""
            mount -o bind "$j" "$absMountpoint"
            local ret=$?
            if [ $ret != "0" ]
            then
               echo "ERROR: At line $line of \"$fsTabFile\": Can not mount \"$j\" to \"$absMountpoint\"! Return=$ret" 1>&2
               sysUnmount "$targetRoot"
               return $ret
            fi
            ((mounts++))
            IS_MOUNTED="${relMountpoint} ${IS_MOUNTED}"
         fi
      done
   done

   [ "$mounts" = "0" ] && echo "WARNING: Could not made any mount of the items of \"$fsTabFile\"!"

   return 0
}

#------------------------------------------------------------------------------
getPathToRoot()
{
   local target=$1

   if [ -d "$target" ]
   then
      if $(hasRootFilesystem $target)
      then
         NEW_ROOT=$target
         $DO_MOUNT_FSTAB_ITEMS && echo "WARNING: Target-root \"$target\" is a directory, therefore it's not possible to process the \"fstab\"!"
         return 0
      fi
      echo "ERROR: No root-filesystem found in \"$target\"!" 1>&2
      return 1
   fi

   if [ "${#target}" = "1" ]
   then
      target=${DEVICE_PREFIX}${target}
   fi

   if [ -b "$target" ] && ! $(isPermitted $target)
   then
      if [ "$?" != "0" ]  #TODO Funktioniert so nicht
      then
         echo "ERROR: Permission-list \"${PREMISSION_FILE}\" not found!" 1>&2
         return 1
      fi
      echo "ERROR: Blockdevice \"$target\" is not permitted!" 1>&2
      echo "Permitted devices in \"${PREMISSION_FILE}\":" 1>&2
      listPermissions 1>&2
      return 1
   fi

   if  ( [ -f "$target" ] || [ -b "$target" ] ) && [ -x "$IMAGE_MOUNTER" ]
   then
       local partitionTable=$($IMAGE_MOUNTER -i $target $MOUNTPOINT )
       if [ ! -n "$partitionTable" ]
       then
          $IMAGE_MOUNTER $IMOUNT_OPTIONS $target $MOUNTPOINT
          local ret=$?
          [ "$ret" != "0" ] && return $ret
          partitionTable=$($IMAGE_MOUNTER -i $target $MOUNTPOINT)
          IMAGE_FILE_NAME=$target
       elif $DO_VERBOSE
       then
          echo "INFO: Image \"${target}\" is already mounted."
       fi

       local i
       IFS=$'\n'
       for i in $partitionTable
       do
          unset IFS
          if $(hasRootFilesystem $i)
          then
             NEW_ROOT=$i
             $DO_VERBOSE && echo "INFO: Found root-partition \"$NEW_ROOT\" of \"$target\"."
             ret="0"
             if $DO_MOUNT_FSTAB_ITEMS
             then
                mountFstabItems "$partitionTable" "$NEW_ROOT"
                ret=$?
             fi
             [ "$ret" != "0" ] && unmountPartitions
             return $ret
          fi
       done
       unmountPartitions
       echo "ERROR No root-partition found in \"$target\"! Dirs: \"$partitionTable\"" 1>&2
       return 1
   fi

   echo "ERROR: I dont know how to handle this: \"$target\"!" 1>&2
   return 1
}

#------------------------------------------------------------------------------
# Input: Path to the root directory.
getCpuName()
{
   LANG=C
   local originFile=$(readlink -m "${1}${TEST_FILE}")
   if [ ! -e "$originFile" ]
   then
      originFile=${1}/${originFile}
   fi
   local cpuName=$(file ${originFile} | awk -F ', ' '{print tolower($2)}')
   case "${cpuName}" in
      "intel 80386") echo "i386" ;;
      *) echo "$cpuName" ;;
   esac
}

#------------------------------------------------------------------------------
# Input: CPU-Name
getEmulatorName()
{
   local cpuName=$1
   local enulatorPath

   enulatorPath=$(which "qemu-${cpuName}-static" 2>/dev/null)
   if [ -n "$enulatorPath" ]
   then
      echo "$enulatorPath"
      return 0
   fi

   enulatorPath=$(which "qemu-${cpuName}" 2>/dev/null)
   if [ -n "$enulatorPath" ]
   then
      if [ ! -n "$(ldd "$enulatorPath" 2>/dev/null | grep "lib" )" ]
      then
         echo "$enulatorPath"
         return 0
      fi
   fi

   echo "nix"
   return 1
}

#------------------------------------------------------------------------------
getMagic()
{
   local cpu=$1

   local magic=""
   local mask=""
   local offset
   case $cpu in
      "arm")
         magic="\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00"
          mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
        offset=""
      ;;
      "i386") #TODO Maske prüfen!!!
         magic="\x7f\x45\x4c\x46\x01\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x02\x03\x00\x01"
          mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
        offset=""
      ;;
      #TODO: Type pattern for other CPU's here!
      *)
         echo ""
         return
      ;;
   esac

   echo ":${cpu}:M:${offset}:${magic}:${mask}:"
}

#------------------------------------------------------------------------------
registerEmulator()
{
   local emulator=$1
   local cpu=$2

   local registerDir="/proc/sys/fs/binfmt_misc"
   local registerFileName="register"

   if [ ! -n "$(mount | grep "$registerDir")" ]
   then
      $DO_VERBOSE && echo "INFO: Mount \"binfmt_misc\" to \"$registerDir\"."
      mount binfmt_misc -t binfmt_misc $registerDir 2>/dev/null
      local ret=$?
      if [ "$ret" != "0" ]
      then
         echo "ERROR: Unable to mount \"binfmt_misc\" to \"$registerDir\" return=$ret !" 1>&2
         return $ret
      fi
   fi

   if [ ! -f "${registerDir}/${cpu}" ]
   then
      local magic=$(getMagic "$cpu")
      if [ ! -n "$magic" ]
      then
          echo "ERROR: Don't know the pattern of executable binary files for the cpu: \"${cpu}\"!" 1>&2
          return 1
      fi

      magic="${magic}${emulator}:"
      local registerFile="${registerDir}/${registerFileName}"

      if [ ! -f "$registerFile" ]
      then
         echo "ERROR: File \"$registerFile\" not found!" 1>&2
         return 1
      fi

      echo $magic > $registerFile 2>/dev/null
      ret=$?
      if [ "$ret" != "0" ]
      then
         echo "ERROR: Unable to register emulator \"$emulator\" for CPU \"$cpu\" in \"$registerFile\", return=$ret!" 1>&2
         echo "       Content of register file shall be:" 1>&2
         echo $magic 1>&2
         return $ret
      fi

      $DO_VERBOSE && echo "INFO: Emulator \"$emulator\" for CPU \"$cpu\" registered in \"${registerFile}\"."

   elif $DO_VERBOSE
   then
      echo "INFO: Emulator \"${emulator}\" already registered."
   fi

   return 0
}

#------------------------------------------------------------------------------
cleanTargetRoot()
{
   local targetRoot=$1
   local emulator=$2

   if [ -f "${targetRoot}${XAUTHORITY}" ]
   then
      $DO_VERBOSE && echo "INFO: Deleting \"${targetRoot}${XAUTHORITY}\""
      rm ${targetRoot}${XAUTHORITY}
   fi

   if [ -x "${targetRoot}${emulator}" ] && [ -x "${emulator}" ] && $IS_EMULATOR_COPIED
   then
      $DO_VERBOSE && echo "INFO: Deleting host-binary \"${targetRoot}${emulator}\""
      rm ${targetRoot}${emulator}
   fi

   reEnableFiles $targetRoot
   sysUnmount $targetRoot
   unmountPartitions
}

#------------------------------------------------------------------------------
isNotMounted()
{ #TODO: Überfrüfen!
   local rootDir=$1
   local device=$2

   if [ -n "$(mount | grep "$(readlink -m ${rootDir})/${device}")" ]
   then
      echo false
   else
      echo true
   fi
}

#------------------------------------------------------------------------------
sysMount()
{
   local targetRoot=$1
   local toMount=$2

   if $(isNotMounted ${targetRoot} ${toMount} )
   then
      local mountpoint="${targetRoot}${toMount}"
      if [ ! -d "${mountpoint}" ]
      then
         echo "WARNING: Mountpoint \"${mountpoint}\" not found!"
         local answer
         read -p "Continue? [y]: " answer
         [ "$answer" = "y" ] && return 0 || return 1
      fi
      $DO_VERBOSE && echo "INFO: Mount \"${toMount}\" to \"${mountpoint}\"."
      mount -o bind ${toMount} "${mountpoint}"
      local ret=$?
      if [ "$ret" != "0" ]
      then
         echo "ERROR: Unable to mount \"${mountpoint}\" return=$ret" 1>&2
         return $ret
      fi
      IS_MOUNTED="${toMount} ${IS_MOUNTED}"
   fi
   return 0
}

#------------------------------------------------------------------------------
prepareTargetRoot()
{
   local targetRoot=$1
   local emulator=$2

   local IFS=:
   for i in $TO_MOUNT
   do
      sysMount $targetRoot $i
      local ret=$?
      if [ "$ret" != "0" ]
      then
         cleanTargetRoot $targetRoot $emulator
         return $ret
      fi
   done
   unset IFS

   disableFiles $targetRoot
   ret=$?
   if [ "$ret" != "0" ]
   then
      cleanTargetRoot $targetRoot $emulator
      return $ret
   fi

   if [ -x "${emulator}" ]
   then
      if [ ! -x "${targetRoot}${emulator}" ] || $DO_FORCE_EMULATOR_COPY
      then
         $DO_VERBOSE && echo "INFO: Copy \"${emulator}\" to \"${targetRoot}${emulator}\""
         cp ${emulator} ${targetRoot}${emulator} 2>/dev/null
         ret=$?
         if [ "$ret" != "0" ]
         then
            cleanTargetRoot $targetRoot $emulator
            echo "ERROR: Unable to copy \"${emulator}\" to \"${targetRoot}${emulator}\" return=$ret !" 1>&2
            return $ret
         fi
      else
         echo "WARNING: Emulator \"${emulator}\" always copied!"
      fi
      IS_EMULATOR_COPIED=true
   fi

   if $DO_USE_X11
   then
      if [ ! -n  "$DISPLAY" ]
      then
         DISPLAY=:0
         $DO_VERBOSE && echo "INFO: DISPLAY=$DISPLAY"
      fi
      $DO_VERBOSE && echo "INFO: Extracting \"${X_AUTHORITY_FILE}\" to \"${targetRoot}\""
      local msg=$(xauth nextract - $DISPLAY 2<&1 | xauth -f "${targetRoot}/${X_AUTHORITY_FILE}" nmerge - 2>&1)
      ret=$?
      $DO_VERBOSE && echo "INFO: $msg"
      if [ "$ret" != "0"  ]
      then
         cleanTargetRoot $targetRoot $emulator
         echo "ERROR: Could not extract \"${targetRoot}/${X_AUTHORITY_FILE}\": $msg" 1>&2
         return $ret
      fi
      export XAUTHORITY="/${X_AUTHORITY_FILE}"
      $DO_VERBOSE && echo "INFO: export XAUTHORITY=${XAUTHORITY}"
   fi

   return 0
}

#------------------------------------------------------------------------------
execChangeRoot()
{
   getPathToRoot $1
   local ret=$?
   [ "$ret" != "0" ] && return $ret

   local targetRoot=$NEW_ROOT

   shift

   local cpuName=$(getCpuName $targetRoot)
   if [ ! -n "$cpuName" ]
   then
      unmountPartitions # $targetRoot
      echo "ERROR: This directory \"$targetRoot\" contains possibly not a linux system!" 1>&2
      return 1
   fi
   $DO_VERBOSE && echo "INFO: CPU for root-directoty \"$targetRoot\" is \"$cpuName\"."

   if [ "$cpuName" != $(getCpuName) ]
   then
      local emulator=$(getEmulatorName "$cpuName")
      if [ ! -n "$emulator" ]
      then
      unmountPartitions # $targetRoot
         echo "ERROR: Emulator for CPU \"$cpuName\" not found!" 1>&2
         return 2
      fi
      $DO_VERBOSE && echo "INFO: Emulator is: \"${emulator##*/}\"."

      registerEmulator "$emulator" "$cpuName"
      ret=$?
      if [ "$ret" != "0" ]
      then
         unmountPartitions
         return $ret
      fi
   else
      emulator=""
      $DO_VERBOSE && echo "INFO: No emulator necessary."
   fi

   prepareTargetRoot $targetRoot $emulator
   ret=$?
   if [ "$ret" != "0" ]
   then
      return $ret
   fi

   if [ -x "${ENTER_EXEC% *}" ]
   then
      $DO_VERBOSE && echo "INFO: Executing \"$ENTER_EXEC $targetRoot\"."
      $ENTER_EXEC $targetRoot
      ret=$?
      if [ "$ret" != "0" ]
      then
         cleanTargetRoot $targetRoot $emulator
         echo "ERROR: \"$ENTER_EXEC $targetRoot\" returns with: \"$ret\"!" 1>&2
         return $ret
      fi
   fi

   if $DO_VERBOSE
   then
      echo "INFO: Entering in chroot \"$targetRoot\" for emulating CPU \"$cpuName\"."
      echo "INFO: PID=$$"
      echo
      if [ ! -n "$1" ]
      then
         echo " **************************"
         echo " * Type \"exit\" to leave.  *"
         echo " **************************"
      fi
   fi
   if [ -n "$1" ]
   then
      chroot $targetRoot $@
   else
      chroot $targetRoot $DEFAULT_TARGET_PROGRAM
   fi
   local chrootRet=$?

   if [ -x "${LEAVE_EXEC% *}" ]
   then
      $DO_VERBOSE && echo "INFO: Executing \"$LEAVE_EXEC $leaveOpt $targetRoot $chrootRet\"."
      $LEAVE_EXEC $targetRoot $chrootRet
      ret=$?
      if [ "$ret" != "0" ]
      then
         cleanTargetRoot $targetRoot $emulator
         echo "ERROR: \"$LEAVE_EXEC $targetRoot $chrootRet\" returns with: \"$ret\"!" 1>&2
         return $ret
      fi
   fi

   cleanTargetRoot $targetRoot $emulator

   [ "$chrootRet" != "0" ] && echo "ERROR: chroot returns with: \"$chrootRet\"!" 1>&2
   return $chrootRet
}

#------------------------------------------------------------------------------
isExecutable()
{
   local name=${1%" *"}

   if [ ! -e "$name" ]
   then
      echo "ERROR: \"$name\" not found!" 1>&2
      return 1
   fi

   if [ ! -s "$name" ]
   then
      echo "ERROR: \"$name\" is invalid!" 1>&2
      return 1
   fi

   if [ ! -x "$name" ]
   then
      echo "ERROR: \"$name\" is not executable!" 1>&2
      return 2
   fi

   return 0
}

#==============================================================================
ARG_ERROR=false
while [ "${1:0:1}" = "-" ]
do
   A=${1#-}
   while [ -n "$A" ]
   do
      case ${A:0:1} in
         "v")
            DO_VERBOSE=true
            IMOUNT_OPTIONS="${IMOUNT_OPTIONS}-v"
         ;;
         "h")
            DO_PRINT_HELP=true
         ;;
         "l")
            DO_LIST_PERMITTED_BLOCK_DEVICES=true
         ;;
         "f")
            DO_MOUNT_FSTAB_ITEMS=true
         ;;
         "x")
            DO_USE_X11=true
         ;;
         "m")
            DO_MOUNT_HOST_FS=true
            if [ "${A:1:1}" == "=" ]
            then
               TO_MOUNT=${A##*=}
               A=""
            elif [ "${A:1:1}" == "+" ]
            then
               TO_MOUNT="${DEFAULT_MOUNTLIST}:${A##*+}"
               A=""
            fi
         ;;
         "p")
            if [ "${A:1:1}" != "=" ]
            then
               echo "ERROR: Missing \"=\" after option \"${A:0:1}\"!" 1>&2
               ARG_ERROR=true
            else
               MOUNTPOINT=${A##*=}
               A=""
            fi
         ;;
         "-")
            B=${A#*-}
            case ${B%=*} in
               "enter")
                  ENTER_EXEC=${A##*=}
               ;;
               "leave")
                  LEAVE_EXEC=${A##*=}
               ;;
               "help")
                  DO_PRINT_HELP=true
               ;;
               "version")
                  DO_PRINT_VERSION=true
               ;;
               *)
                  echo "ERROR: Unknown option \"-${A}\"!" 1>&2
                  ARG_ERROR=true
               ;;
            esac
            A=""
         ;;
         *)
            echo "ERROR: Unknown option: \"${A:0:1}\"!" 1>&2
            ARG_ERROR=true
         ;;
      esac
      A=${A#?}
   done
   shift
done
if $ARG_ERROR
then
   printHelp 1>&2
   exit 1
fi

if $DO_PRINT_HELP
then
   printHelp
   exit 0
fi

if $DO_PRINT_VERSION
then
   echo "Cross-chroot: $VERSION"
   [ -x "$IMAGE_MOUNTER" ] && $IMAGE_MOUNTER --version
   exit 0
fi

if $DO_LIST_PERMITTED_BLOCK_DEVICES
then
   $DO_VERBOSE && echo "INFO: Permitted devices:"
   listPermissions
   exit $?
fi

if [ ! -n "$(which chroot 2>/dev/null)" ]
then
   echo "ERROR: Can not find program \"chroot\". Possibly not installed!" 1>&2
   exit 1
fi

if [ $UID -ne 0 ]
then
   echo "Not allow, because you are not root!"
   echo "Try: sudo $PROG_NAME $@"
   exit 1
fi

if [ ! -n "$1" ]
then
   printHelp 1>&2
   echo "ERROR: Missing argument" 1>&2
   exit 1
fi

$DO_VERBOSE && echo "INFO: Checking whether a instance of this program by the same image is already running..."
OWN_PID=$$
PID=$(isRunning $OWN_PID $0 $1 $2 )
if [ -n "$PID" ]
then
   echo "WARNING: Process with the same argument \"$1\" is already running!"
   echo "         Process-id = $PID"
   read -p "Terminate it? [y]" ANSWER
   if [ "$ANSWER" = "y" ]
   then
       kill $PID
       RET=$?
       echo "Exit. Try again."
       exit $RET
   fi
   echo "Exit"
   exit 0
fi

if [ ! -x "$IMAGE_MOUNTER" ]
then
   echo "WARNING: Image-mounter \"$IMAGE_MOUNTER\" not found!"
   echo "         Therefore it's impossible to make a change-root for image-files or block-devices!"
   IMAGE_MOUNTER=""
fi

if [ ! -n "$MOUNTPOINT" ]
then
   if [ -d "$DEFAULT_MOUNTPOINT" ]
   then
      MOUNTPOINT=$DEFAULT_MOUNTPOINT
   else
      MOUNTPOINT="."
   fi
fi

RET1="0"
RET2="0"
if [ -n "$ENTER_EXEC" ]
then
   isExecutable $ENTER_EXEC
   RET1=$?
fi
if [ -n "$LEAVE_EXEC" ]
then
   isExecutable $LEAVE_EXEC
   RET2=$?
fi
if [ "$RET1" != "0" ] || [ "$RET2" != "0" ]
then
   exit 1
fi

if $DO_MOUNT_HOST_FS && [ ! -n "$TO_MOUNT" ]
then
   TO_MOUNT=$DEFAULT_MOUNTLIST
fi

if $DO_USE_X11 && [ ! -n "$(echo "$TO_MOUNT" | grep "$X11_MOUNT" )" ]
then
   if [ -n "$TO_MOUNT" ]
   then
      TO_MOUNT="${TO_MOUNT}:${X11_MOUNT}"
   else
      TO_MOUNT="${X11_MOUNT}"
   fi
fi

execChangeRoot $@
RET=$?

exit $RET
#=================================== EOF ======================================


