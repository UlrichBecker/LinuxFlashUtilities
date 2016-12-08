#!/bin/bash
###############################################################################
##                                                                           ##
##                             Imagemounter                                  ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     imount.sh                                                       ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     06.12.2013                                                      ##
## Revision: 28.11.2016 using sfdisk                                         ##
###############################################################################
#  Copyright 2013 INKATRON                                                    #
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
# $Id: imount.sh,v 1.38 2014/10/15 16:20:21 uli Exp $
VERSION=1.15
MOUNT=mount
UMOUNT=umount
PATH="/sbin:/usr/sbin:$PATH"
ACCESS_MODE="rw"
DO_VERBOSE=false
DO_NOT_MOUNT=false #!!
DO_MARC_PARTITION_TYPE=false
DO_UNMOUNT=false
DO_REMOVE_MOUNTPOINTS=false
DO_GET_MOUNT_INFO=false
DO_GET_MOUNT_POINT=false
DO_SHOW_EXTENDED_PARTITION=false
DO_SHOW_SWAP_PARTITION=false
DO_PRINT_HELP=false
DO_PRINT_VERSION=false
DO_PREFIX=true
DO_GET_PATH_SEPARATOR_SBSTITUDE=false
DO_LIST_PARTITIONS=false
DO_LIST_PERMISSIONS=false


PATH_SEPARATOR_SUBSTITUDE='+'
BOOT_PARTITION_MARKER="B"
SWAP_PARTITION_MARKER="S"
EXTENDED_PARTITION_MARKER="E"

TO_PROCESSED_PARTITIONS=""
PART_NUMBER_SEPARATOR=','

DEFAULT_MOUNTPOINT="/mnt"
DEFAULT_UNMOUNT_OPTION=""
BYTES_PER_SECTOR=512

DO_CHECK_BLOCK_DEVICES=true
IS_NEW_FDISC_FORMAT=true

if $DO_CHECK_BLOCK_DEVICES
then
   PERMISSION_MODULE="${0%/*}/dev_permissions.sh"
   source $PERMISSION_MODULE 2>/dev/null
   RET=$?
   if [ "$RET" != "0" ]
   then
      echo "ERROR: Module \"${PERMISSION_MODULE}\" not found!" 1>&2
      exit $RET
   fi
   ADDITIONAL_HELP_TEXT="-l           List all permitted block-devices."
fi

#------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

Imagefile-Mounter and Unmounter
$(basename $(readlink -m ${0##*/})): (C) 2014 www.INKATRON.de
Author: Ulrich Becker
Version: $VERSION

Usage: ${0##*/} [-options] <imagefile or block-device> [mountpoint]
If [mountpoint] not given, the default "$DEFAULT_MOUNTPOINT" will be used.

Options:
   -h, --help   This help.
   -u           Unmount.
   -U           Unmount and remove mountpoint-directorys if possible.
   -n           Do not mount (simulate only).
   -v           Verbose.
   -i           Get mount-infos if <image-file or block-device> mounted.
   $ADDITIONAL_HELP_TEXT
   -l           List of permitted block-devices.
   -L           List numbers of found partitions of <image-file or block-device> and mountpoints if corresponding partition mounted by "${0##*/}".
   -E           Show extended partitions by option -L.
   -S           Show swap partition by option -L.
   -N           No prefix (${PATH_SEPARATOR_SUBSTITUDE}path${PATH_SEPARATOR_SUBSTITUDE}to${PATH_SEPARATOR_SUBSTITUDE}imagefile${PATH_SEPARATOR_SUBSTITUDE}) for the partition-mountpoints.
   -s           Get substitute character of path-separator.
   -p           Display base-mountpoint of <image-file> if mounted.

   -P=< "$PART_NUMBER_SEPARATOR" separated list of partition-numbers to process>
                Partition-numbers to process will be indicated by option "-L".
                If this option not given, all found mountable partitions will
                mount (or unmount by option "-U" or "-u").
   --version    Version-number

__EOH__
}

#------------------------------------------------------------------------------
getNumber()
{
   echo ${1##*[!0-9]}
}

#------------------------------------------------------------------------------
canProcessed()
{
   if [ ! -n "$TO_PROCESSED_PARTITIONS" ]
   then
      echo true
      return 0
   fi

   local n=$(getNumber $1)
   local i
   local IFS=$PART_NUMBER_SEPARATOR
   for i in $TO_PROCESSED_PARTITIONS
   do
      unset IFS
      if [ "$i" = "$n" ]
      then
         echo true
         return 0
      fi
   done
   echo false
}

#------------------------------------------------------------------------------
getNumOfDirItems()
{
   local items=0
   local i
   for i in $(ls $1)
   do
      ((items++))
   done
   echo $items
}

#------------------------------------------------------------------------------
getPrefix()
{
   if $DO_PREFIX
   then
      if [ "$IMAGE_FILE" != "$(basename $IMAGE_FILE)" ]
      then
         local path=$(readlink -m "${IMAGE_FILE%/*}")
      else
         local path=$(pwd)
      fi
      echo "$(echo $path | tr '/' ${PATH_SEPARATOR_SUBSTITUDE})${PATH_SEPARATOR_SUBSTITUDE}"
   else
      echo ""
   fi
}

#------------------------------------------------------------------------------
getMountInfo()
{
   local i
   local IFS=$'\n'
   for i in $(df | grep "${BASE_MOUNTPOINT}/$(getPrefix)${IMAGE_FILE##*/}[0-9]")
   do
      echo ${i##*' '}
   done
   unset IFS
}

#------------------------------------------------------------------------------
getBaseMountPoint()
{
   local i
   local IFS=$'\n'
   for i in $(getMountInfo)
   do
      echo ${i%/*}
      unset IFS
      return 0
   done
   unset IFS
}

#------------------------------------------------------------------------------
getPartitionTable()
{
   LANG=C
   local i
   local IFS=$'\n'
   for i in $(sfdisk -d $1 2>/dev/null | grep "$1[0-9]")
   do
      [ $(echo $i | awk -F= '{print $3}' | awk -F, '{print $1}') -eq 0 ] && continue
      echo $i
   done
}

#------------------------------------------------------------------------------
hasPartitions()
{
   if [ -n  "$(getPartitionTable $1)" ]
   then
      echo true
   else
      echo false
   fi
}

#------------------------------------------------------------------------------
listPartitions()
{
   local i
   LANG=C
   local list=$(getPartitionTable $IMAGE_FILE)
   if [ ! -n "$list" ]
   then
      $DO_VERBOSE && echo "INFO: No partitions found in \"$IMAGE_FILE\"!"
      return 0
   fi
   local mountList=$(getMountInfo)

   $DO_VERBOSE && printf "PartNr.\t\tid\tsize\t\tmounted\n"

   local IFS=$'\n'
   for i in $list
   do
      unset IFS
      local id=$(echo $i | awk -F= '{print $4}' | awk -F, '{print $1}')
      case $id in
         " 5"|" f"|"85"|"a2")
            $DO_SHOW_EXTENDED_PARTITION || continue
         ;;
         "82")
            $DO_SHOW_SWAP_PARTITION || continue
         ;;
      esac
      local size=$(($(echo $i | awk -F= '{print $3}' | awk -F, '{print $1}') * ${BYTES_PER_SECTOR}))
      local partitionNr=$(getNumber $(echo "$i" | awk '{print $1}'))
      local mountpoint="-"
      local IFS=$'\n'
      for j in $mountList
      do
         unset IFS
         if [ "$partitionNr" = "$(getNumber $j)" ]
         then
            mountpoint=$j
         fi
      done
      printf "%s\t\t%s\t%s\t\t%s\n" $partitionNr $id $size $mountpoint
   done
}

#------------------------------------------------------------------------------
unmountImage()
{
   if [ -n "$1" ]
   then
      local baseMountpoint=$1
   else
      local baseMountpoint=$(getBaseMountPoint)
      if [ ! -n "$baseMountpoint" ]
      then
         $DO_VERBOSE && echo "INFO: Nothing to unmount!"
         return 0
      fi
   fi

   local i
   for i in $(getMountInfo)
   do
      if ! $DO_NOT_MOUNT
      then
         $(canProcessed $i) || continue
         local option=$DEFAULT_UNMOUNT_OPTION
         local umountCount=1
         ret=-1
         while [ "$ret" != "0" ]
         do
            $DO_VERBOSE && echo "INFO: Unmount partition: \"$i\" by option: \"$option\"."
            $UMOUNT $option "$i"
            ret=$?
            if [ "$ret" != "0" ]
            then
               ((umountCount++))
               echo "ERROR: Impossible to unmount partition: \"$i\"! Returncode: $ret" 1>&2
               echo "       Partition \"$i\" is possibly still used." 1>&2
               echo "       $(fuser -a "${i}")" 1>&2
               read -p "Retry $umountCount ? Type \"y\", by option -l type \"l\", by option -f type \"f\", fuser -k type \"k\", continue type \"c\": " ANSWER
               case $ANSWER in
                  "y")
                     option=$DEFAULT_UNMOUNT_OPTION
                  ;;
                  "l"|"f")
                     option="-${ANSWER}"
                  ;;
                  "k")
                     $DO_VERBOSE && echo "INFO: \"Run fuser -ki $i\""
                     echo "y" | fuser -ki "$i"
                     sleep 1
                     option=$DEFAULT_UNMOUNT_OPTION
                  ;;
                  "c")
                     ret=0
                  ;;
                  *)
                     echo "Exit by user!"
                     exit $ret
                  ;;
               esac
            fi
         done
      fi
      if $DO_REMOVE_MOUNTPOINTS
      then
         if [ $(getNumOfDirItems ${i} ) == "0" ]
         then
            if $DO_VERBOSE || $DO_NOT_MOUNT
            then
               echo "INFO: Remove directory:  \"$i\""
            fi
            if ! $DO_NOT_MOUNT
            then
               rmdir $i
            fi
         else
            echo "WARNING: Directory \"${i}\" is not empty. Impossible to remove it!"
         fi
      fi
   done

   if $DO_REMOVE_MOUNTPOINTS && [ "$baseMountpoint" != "$DEFAULT_MOUNTPOINT"  ]
   then
      if  [ $(getNumOfDirItems ${baseMountpoint} ) == "0" ]
      then
         if $DO_VERBOSE || $DO_NOT_MOUNT
         then
            echo "INFO: Remove directory: \"${baseMountpoint}\""
         fi
         if ! $DO_NOT_MOUNT
         then
            rmdir $baseMountpoint
         fi
      else
         echo "WARNING: Directory \"${baseMountpoint}\" is not empty. Impossible to remove it!" 1>&2
      fi
   fi
}

#------------------------------------------------------------------------------
mountImage()
{
   local prefix="$(getPrefix)"

   if [ -n "$(df | grep "${prefix}${IMAGE_FILE##*/}")" ]
   then
      echo "WARNING: This image-file \"${IMAGE_FILE}\" is possibly already mounted!"
      read -p "Try to mount any way [y]? " ANSWER
      if [ "$ANSWER" != "y" ]
      then
         echo "Exit by user!"
         exit 1
      fi
   fi

   if [ ! -d "$BASE_MOUNTPOINT" ]
   then
      if $DO_VERBOSE || $DO_NOT_MOUNT
      then
         echo "INFO: Creating directory: "$BASE_MOUNTPOINT
      fi
      if ! $DO_NOT_MOUNT
      then
         mkdir $BASE_MOUNTPOINT
         if [ "$?" != "0" ]
         then
            exit $?
         fi
      fi
   fi

   if $(hasPartitions $IMAGE_FILE)
   then
      local IFS=$'\n'
      for i in $(getPartitionTable $IMAGE_FILE)
      do
         local sectorOffset=$(echo $i | awk -F= '{print $2}' | awk -F, '{print $1}')
         case $(echo $i | awk -F= '{print $4}' | awk -F, '{print $1}') in
            " 5"|" f"|"85"|"a2")
               $DO_VERBOSE && echo "INFO: Ignore extended partition at sector: ${sectorOffset}. Name: \"${name}\""
               continue
            ;;
            "82")
               $DO_VERBOSE && echo "INFO: Ignore swap partition at sector: ${sectorOffset}. Name: \"${name}\""
               continue
            ;;
         esac
         local partition=$(echo $i | awk '{print $1}')

         $(canProcessed $partition) || continue

         local partMountpoint=${BASE_MOUNTPOINT}"/${prefix}${partition##*/}${ext}"

         if [ ! -d $partMountpoint ]
         then
            if $DO_VERBOSE || $DO_NOT_MOUNT
            then
               echo "INFO: Creating directory: \"$partMountpoint\"."
            fi
            if ! $DO_NOT_MOUNT
            then
               mkdir $partMountpoint
               local ret=$?
               if [ "$ret" != "0" ]
               then
                  exit $ret
               fi
            fi
         fi

         local byteOffset=$(($sectorOffset * $BYTES_PER_SECTOR))
         local psize=$(($(echo $i | awk -F= '{print $3}' | awk -F, '{print $1}') * ${BYTES_PER_SECTOR}))

         ($DO_VERBOSE || $DO_NOT_MOUNT) && echo -e "INFO: Mount partition of: \"${IMAGE_FILE}\"\n" \
                                                " to \"${partMountpoint}\"\n" \
                                                " at offset: ${byteOffset}\n" \
                                                " size:      ${psize}\n  name: \"${name}\""
         if ! $DO_NOT_MOUNT
         then
            $MOUNT -o loop,${ACCESS_MODE},offset=${byteOffset},sizelimit=${psize} $IMAGE_FILE $partMountpoint
            ret=$?
         fi
         if [ "$ret" != "0" ]
         then
            echo "ERROR: Unable to mount partition: \"${partition##*/}\"!" 1>&2
            read -p "Continue? [y] " ANSWER  1>&2
            if [ "$ANSWER" != "y" ]
            then
               unmountImage $BASE_MOUNTPOINT
               echo "Exit by user!"
               exit $ret
            fi
         fi
      done
   else # End of partitions found, begin of no partitions found.
      $DO_VERBOSE && echo "INFO: No partitions found in \"${IMAGE_FILE}\"."
      partMountpoint="${BASE_MOUNTPOINT}/${prefix}${IMAGE_FILE##*/}0"
      if [ ! -d "$partMountpoint" ]
      then
         if $DO_VERBOSE || $DO_NOT_MOUNT
         then
            echo "INFO: Creating directory: \"${partMountpoint}\"."
         fi
         if ! $DO_NOT_MOUNT
         then
            mkdir $partMountpoint
         fi
      fi
      if $DO_VERBOSE || $DO_NOT_MOUNT
      then
         echo "INFO: mount \"${IMAGE_FILE}\" to \"${partMountpoint}\""
      fi
      if ! $DO_NOT_MOUNT
      then
         $MOUNT $IMAGE_FILE $partMountpoint
         ret=$?
         if [ "$ret" != "0" ]
         then
            if $DO_VERBOSE
            then
               echo "INFO: Remove directory: \"${partMountpoint}\"."
            fi
            rmdir $partMountpoint
            echo "ERROR: Unable to mount image-file or block-device: \"${IMAGE_FILE##*/}\"!" 1>&2
            exit $ret
         fi
      fi
   fi
}

#================================= MAIN =======================================
ARGS=$@
ARG_ERROR=false
while [ "${1:0:1}" = "-" ]
do
   A=${1#-}
   while [ -n "$A" ]
   do
      case ${A:0:1} in
         "v")
            DO_VERBOSE=true
         ;;
         "m")
            DO_MARC_PARTITION_TYPE=true
         ;;
         "n")
            DO_NOT_MOUNT=true
         ;;
         "u")
            DO_UNMOUNT=true
            DO_REMOVE_MOUNTPOINTS=false
         ;;
         "U")
            DO_UNMOUNT=true
            DO_REMOVE_MOUNTPOINTS=true
         ;;
         "i")
            DO_GET_MOUNT_INFO=true
         ;;
         "p")
            DO_GET_MOUNT_POINT=true
         ;;
         "E")
            DO_SHOW_EXTENDED_PARTITION=true
         ;;
         "S")
            DO_SHOW_SWAP_PARTITION=true
         ;;
         "h")
            DO_PRINT_HELP=true
         ;;
         "l")
            DO_LIST_PERMISSIONS=$DO_CHECK_BLOCK_DEVICES
         ;;
         "L")
            DO_LIST_PARTITIONS=true
         ;;
         "N")
            DO_PREFIX=false
         ;;
         "s")
            DO_GET_PATH_SEPARATOR_SBSTITUDE=true
         ;;
         "P")
            if [ "${A:1:1}" != "=" ]
            then
               echo "ERROR: Missing \"=\" after option \"${A:0:1}\"!" 1>&2
               ARG_ERROR=true
            else
               TO_PROCESSED_PARTITIONS=${A##*=}
               A=""
            fi
         ;;
         "-")
            case ${A#*-} in
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
   printHelp
   exit 1
fi

if $DO_LIST_PERMISSIONS
then
   $DO_VERBOSE && echo "INFO: Permitted devices:"
   listPermissions
   exit 0
fi

if $DO_GET_PATH_SEPARATOR_SBSTITUDE
then
   echo $PATH_SEPARATOR_SUBSTITUDE
   exit 0
fi

if $DO_PRINT_HELP
then
   printHelp
   exit 0
fi

if $DO_PRINT_VERSION
then
   echo "Imagemounter: $VERSION"
   exit 0
fi

if [ ! -n "$(which sfdisk 2>/dev/null)" ]
then
   echo "ERROR: Can not find program \"sfdisk\". Possibly not installed!" 1>&2
   exit 1
fi

if [ $# -lt 1 ]
then
   echo "ERROR: Missing argument!" 1>&2
   printHelp 1>&2
   exit 1
fi

IMAGE_FILE="$1"
$DO_CHECK_BLOCK_DEVICES && IMAGE_FILE=$(getBlockDeviceName "$IMAGE_FILE")

if [ ! -e $IMAGE_FILE ]
then
   echo "ERROR: Can not find \"$IMAGE_FILE\"!" 1>&2
   exit 1
fi

if $DO_LIST_PARTITIONS
then
   listPartitions
   exit 0
fi

if $DO_GET_MOUNT_INFO
then
   BASE_MOUNTPOINT=$2
   getMountInfo
   exit 0
fi

if $DO_GET_MOUNT_POINT
then
   getBaseMountPoint
   exit 0
fi

if [ $UID -ne 0 ] && ! $DO_NOT_MOUNT
then
   echo "Not allow, because you are not root!" 1>&2
   echo "Try: sudo ${0##*/} $ARGS"
   exit 1
fi

if $DO_CHECK_BLOCK_DEVICES && [ -b "$IMAGE_FILE" ]
then
   checkPermissions "$IMAGE_FILE"
   if [ "$?" != "0" ]
   then
      exit 1
   fi
   if [ $(getFileSize "$IMAGE_FILE") = 0 ]
   then
      echo "ERROR: Device on \"$IMAGE_FILE\" possibly not connected!" 1>&2
      exit 1
   fi
fi

if  [ -n "$2" ]
then
   BASE_MOUNTPOINT=$2
else
   BASE_MOUNTPOINT=$DEFAULT_MOUNTPOINT
fi

if $DO_UNMOUNT
then
   unmountImage
else
   if $DO_VERBOSE && [ "$BASE_MOUNTPOINT" != "$DEFAULT_MOUNTPOINT" ]
   then
      echo "INFO: Base-Mountpoint: "$BASE_MOUNTPOINT
   fi
   mountImage
fi

exit $?
#=================================== EOF ====================================== 
