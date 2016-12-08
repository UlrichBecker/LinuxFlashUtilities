#!/bin/bash
###############################################################################
##                                                                           ##
##   Wrapper script of gparted for manipulating partitions of image-files    ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     iparted.sh                                                      ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     11.09.2014                                                      ##
## Revision: 21.12.2015 Accommodation to UBUNTU                              ##
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
# $Id: iparted.sh,v 1.11 2015/01/30 18:39:36 uli Exp $
VERSION=0.3
DO_PRINT_HELP=false
DO_VERBOSE=false
DO_PRINT_VERSION=false
DO_LIST_PERMISSIONS=false
DO_LIST_FOUND_PERMISSIONS=false
DO_SHIRNK_TO_PARTITION=false

PATCH_GPARTED_BUG=true

KPARTX_PATH=""

PERMISSION_MODULE="${0%/*}/dev_permissions.sh"

BYTES_PER_SECTOR=512
BASE=1024

PATH="./:/sbin:/usr/sbin:/usr/local/bin:/usr/bin:${PATH}"

TITLE_PREFIX=${0##*/}

source $PERMISSION_MODULE
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Module \"${PERMISSION_MODULE}\" not found!" 1>&2
   exit $RET
fi

#------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

Partition-Editor for image-files
(C) 2014 www.INKATRON.de
Author: Ulrich Becker

Usage:  ${0##*/} [options] [Imagefile | Block-device] [Desired entire imagefile-size | possible target block-device]

Block-devices are checked in "$PREMISSION_FILE"

Options:
   -h, --help     This help.
   -v             Verbose.
   -s, --shrink   Shrink filesize of the imagefile to the border of the highest partition.
   -l             List all permitted block-devices of "$PREMISSION_FILE"
   -c             List all connected permitted block-devices of "$PREMISSION_FILE"
   --version      Print version and exit.

__EOH__
}

#------------------------------------------------------------------------------
errorMsg()
{
   Xdialog --fixed-font --left --title "${TITLE_PREFIX} ERROR" \
           --msgbox "$1" 0 0 2>/dev/null
}

#------------------------------------------------------------------------------
infoMsg()
{
   Xdialog --fixed-font --left --title "${TITLE_PREFIX} INFO" \
           --infobox "$1" 0 0 2>/dev/null
   #[ -n "$2" ] && sleep $2
}

#------------------------------------------------------------------------------
questionYesNo()
{
   Xdialog --fixed-font --left --title "${TITLE_PREFIX} QESTION" \
           --yesno "$1" 0 0 2>/dev/null
   if [ $? = "0" ]
   then
      echo true
   else
      echo false
   fi
   return $?
}

#------------------------------------------------------------------------------
fileMenu()
{
   local sFile

   [ -n "$1" ] && sFile="$1" || sFile="$(pwd)"

   while [ -d "$sFile" ]
   do
      sFile="$(readlink -m "$sFile")"
      sFile=$(Xdialog --fixed-font --left --title "${TITLE_PREFIX}" \
            --fselect "$sFile/" 0 0 3>&1 1>&2 2>&3)
      sFile=${sFile##* }
   done

   [ -n "$sFile" ] || return 1

   if [ ! -f "$sFile" ] && [ ! -b "$sFile" ]
   then
      errorMsg "\"$sFile\" is not a file!"
      return 1
   fi

   echo "$sFile"
   return 0
}

#-----------------------------------------------------------------------------
sizeInputDlg()
{
   local fileSize
   fileSize=$(Xdialog --fixed-font --left --title "${TITLE_PREFIX}" \
            --inputbox "Entire filesize of\n\"$1\"" 0 0 "$2" 3>&1 1>&2 2>&3)
   echo "$fileSize"
}

#------------------------------------------------------------------------------
human2machine()
{
   if [ -n "$(echo ${1:0:1} | tr -d '[0-9]')" ]
   then
      echo "-1"
      return 1
   fi

   local number=${1//[A-Za-z]}
   local unit=${1##$number}

   number=$(echo $number | tr ',' '.')

   if [ ! -n "$number" ] || [ -n "$(echo $number | tr -d '[0-9]' | tr -d '.')" ]
   then
      echo "-1"
      return 1
   fi

   if [ -n "$unit" ]
   then
      case $unit in
         'B'|'b') ;;
         'KiB')         number=$(echo "$number * 1024" | bc) ;;
         'K'|'KB'|'k')  number=$(echo "$number * 1000" | bc) ;;
         'MiB')         number=$(echo "$number * 1048576" | bc) ;;
         'M'|'MB'|'m')  number=$(echo "$number * 1000000" | bc) ;;
         'GiB')         number=$(echo "$number * 1073741824" | bc) ;;
         'G'|'GB'|'g')  number=$(echo "$number * 1000000000" | bc) ;;
         'TiB')         number=$(echo "$number * 1099511627776" | bc) ;;
         'T'|'TB'|'t')  number=$(echo "$number * 1000000000000" | bc) ;;
         *)
            echo "-1"
            return 1
         ;;
      esac
   fi

   if [ -n "$(echo "$number" | grep '\.')" ]
   then
      local nk=${number##*'.'}
      number=${number%%.*}
      [ "$nk" -gt "0" ] && ((number++))
   fi
   echo $number
   return 0
}

GPARTED_EXT="_part"
#-----------------------------------------------------------------------------
linkPartitionsOfImageFileToLoopDevices()
{
   local loopdevice=$(losetup -f 2>/dev/null)
   if [ ! -n "$loopdevice" ]
   then
      echo ""
      return 1
   fi
   if [ -n "$KPARTX_PATH" ]
   then
      $KPARTX_PATH -a $1 2>/dev/null
   else
      losetup -P $loopdevice $1 2>/dev/null
      #losetup $loopdevice $1 2>/dev/null
   fi
   if [ "$?" = "0" ]
   then
      local i
      for i in $(ls $(dirname ${loopdevice})/mapper/$(basename ${loopdevice})p[0-9] )
      do
         ln -sf "$i" "$(dirname ${loopdevice})/$(basename $i)" #1>&2
      done

      if $PATCH_GPARTED_BUG
      then
         for i in $(ls ${loopdevice}p[0-9] 2>/dev/null)
         do
            ln -sf "$i" "${loopdevice}${GPARTED_EXT}${i##*[!0-9]}" # 2>/dev/null
         done
      fi
      echo $loopdevice
   else
      echo ""
      return 1
   fi
   return 0
}

#------------------------------------------------------------------------------
freeLoopDevice()
{
   local loopdevice="$1"
   local i
   if $PATCH_GPARTED_BUG
   then
      for i in $(ls ${loopdevice}${GPARTED_EXT}[0-9])
      do
         if [ -L "$i" ]
         then
            $DO_VERBOSE && echo "INFO: Removing symbolic link: \"$i\" from \"$(readlink "$i")\""
            rm "$i" 2>/dev/null
         fi
      done
   fi
   for i in $(ls ${loopdevice}p[0-9])
   do
      if [ -L "$i" ]
      then
         $DO_VERBOSE && echo "INFO: Removing symbolic link: \"$i\" from \"$(readlink "$i")\""
         rm "$i" 2>/dev/null
      fi
   done
   $DO_VERBOSE && echo "INFO: Removing loop-devices: " && ls ${loopdevice}*
   if [ -n "$KPARTX_PATH" ]
   then
      $KPARTX_PATH -d $loopdevice
   fi
   losetup -d "$loopdevice"
   local ret=$?
   [ "$ret" != "0" ] && errorMsg "Unable to release loop-devices: \"$loopdevice\", returncode = $ret"
   return $ret
}

#------------------------------------------------------------------------------
exitIfNotPermitted()
{
   if ! $(isPermitted "$1")
   then
      if [ -n "$ERROR" ] #TODO ERROR scheit in einem Kindprozess zu sein.
      then
         errorMsg "$ERROR"
      else
         errorMsg "This block-device \"$(readlink -m "$1")\" is not allow!"
      fi
      exit 1
   fi
}

#------------------------------------------------------------------------------
exitIfMounted()
{
   local mountInfo="$(mount | grep "$(readlink -m "$1")")"
   if [ -n "$mountInfo" ]
   then
      errorMsg "This image\"$1\" is already mounted:\n\n${mountInfo}\n\nPlease unmount it."
      exit 1
   fi
}

#================================== main ======================================
ARG_ERROR=false
while [ "${1:0:1}" = "-" ]
do
   A=${1#-}
   while [ -n "$A" ]
   do
      case ${A:0:1} in
        "h")
            DO_PRINT_HELP=true
        ;;
        "v")
            DO_VERBOSE=true
        ;;
        "s")
            DO_SHIRNK_TO_PARTITION=true
        ;;
        "l")
            DO_LIST_PERMISSIONS=true
        ;;
        "c")
            DO_LIST_FOUND_PERMISSIONS=true
        ;;
        "-")
            case ${A#*-} in
               "help")
                  DO_PRINT_HELP=true
               ;;
               "shrink")
                  DO_SHIRNK_TO_PARTITION=true
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
   exit 1
fi

if $DO_PRINT_VERSION
then
   echo $VERSION
   exit 0
fi

if $DO_PRINT_HELP
then
   printHelp
   exit 0
fi

if ! $(isPresent "Xdialog")
then
   echo "ERROR: Program \"Xdialog\" not installed!" 1>&2
   exit 1
fi

if $DO_LIST_PERMISSIONS
then
   Xdialog --fixed-font --left --title "${TITLE_PREFIX} permitted block-devices" \
   --msgbox "$(listPermissions 2>&1)" 0 0 2>/dev/null
   exit 0
fi

if $DO_LIST_FOUND_PERMISSIONS
then
   Xdialog --fixed-font --left --title "${TITLE_PREFIX} conected permitted block-devices" \
   --msgbox "$(listFuondPermitedDevices 2>&1)" 0 0 2>/dev/null
   exit 0
fi

#KPARTX_PATH=$(which kpartx)

if ! $(isPresent "gparted")
then
   errorMsg "Program \"gparted\" not installed!"
   exit 1
fi

if [ $UID -ne 0 ]
then
   errorMsg "Not allow, because you are not root! \nTry: xsudo ${0##*/}"
   exit 1
fi

if [ -b "$1" ]
then
   IMAGE_FILE="$1"
else
   IMAGE_FILE=$(fileMenu "$1")
   [ $? != 0 ] && exit 1
fi

if [ ! -n "$IMAGE_FILE" ]
then
   errorMsg "Missing image-file!"
   exit 1
fi

if [ -b "$IMAGE_FILE" ] # Is first parameter a block-device?
then
   exitIfNotPermitted "$IMAGE_FILE"
   exitIfMounted "$IMAGE_FILE"
   if [ ! -n "$(getFileSize "$IMAGE_FILE")" ]
   then
      errorMsg "Block-device \"$(readlink -m "$IMAGE_FILE")\" possibly not connected!"
      exit 2
   fi
elif [ -f "$IMAGE_FILE" ] # Is first parameter a image-file?
then
   exitIfMounted "$IMAGE_FILE"
   SIZE="$2"
   USED_FILE_SIZE=$(getSizeViaPartitions "$IMAGE_FILE")
   if [ ! -n "$USED_FILE_SIZE" ]
   then
      errorMsg "Can't find partitions in file \"$IMAGE_FILE\"!"
      exit 3
   fi
   if [ ! -n "$SIZE" ] # Second parameter not present?
   then
      SIZE=$(sizeInputDlg "$IMAGE_FILE" $USED_FILE_SIZE)
   fi
   if [ -n "$SIZE" ]
   then
      if [ -b "$SIZE"  ] # Is Second parameter a block-dewice?
      then
         exitIfNotPermitted "$SIZE"
         INPUT="$SIZE"
         SIZE=$(getFileSize "$SIZE")
         if [ "$SIZE" = "0" ]
         then
            errorMsg "Can't determine the memorysize of \"$INPUT\".\nDevice possibly not connected."
            exit 2
         fi
      else # Suposing second parameter is a desired memorysize.
         INPUT="$SIZE"
         SIZE=$(human2machine "$SIZE")
         if [ "$SIZE" -lt "0" ]
         then
            errorMsg "Wrong input for size: \"$INPUT\""
            exit 2
         fi
      fi
      $DO_VERBOSE && echo "INFO: Desired size: $SIZE"
      if [ "$SIZE" -lt "$USED_FILE_SIZE" ]
      then
         errorMsg "Desired size of: $(toHuman $SIZE $BASE)\n is lower then the\nminimum of \"$(toHuman $USED_FILE_SIZE $BASE)\"\nin \"$IMAGE_FILE\""
         exit 4
      fi
      REAL_FILE_SIZE=$(getFileSize "$IMAGE_FILE")
      if [ "$SIZE" != "$REAL_FILE_SIZE" ]
      then
         if $DO_VERBOSE
         then
            [ "$REAL_FILE_SIZE" -gt "$SIZE" ] && echo "INFO: Shrinking filesize from $(toHuman $REAL_FILE_SIZE $BASE) to $(toHuman $SIZE $BASE) bytes"
            [ "$REAL_FILE_SIZE" -lt "$SIZE" ] && echo "INFO: Growing filesize from $(toHuman $REAL_FILE_SIZE $BASE) to $(toHuman $SIZE $BASE) bytes"
         fi
         truncate -c -s $SIZE "$IMAGE_FILE"
         RET=$?
         if [ "$RET" != "0" ]
         then
            errorMsg "Unable to resize file \"$IMAGE_FILE\" to $SIZE bytes!"
            exit $RET
         fi
      fi
   fi # End for the handling of a possilbe second parameter
else
   errorMsg "Don't know how to handle this:\n\"$IMAGE_FILE\""
   exit 3
fi

LOOP_DEVICE=$(linkPartitionsOfImageFileToLoopDevices "$IMAGE_FILE")
if [ ! -n "$LOOP_DEVICE" ]
then
   errorMsg "Unable to link \"$IMAGE_FILE\"\nto a loop-device!"
   exit 1
fi
$DO_VERBOSE && echo "INFO: Loopdevices for gparted are: \"$(ls -g $LOOP_DEVICE*)\""
gparted $LOOP_DEVICE
RET=$?
freeLoopDevice "$LOOP_DEVICE"

if [ "$RET" = "0" ] && [ ! -b "$IMAGE_FILE" ] && $DO_SHIRNK_TO_PARTITION
then
   USED_FILE_SIZE=$(getSizeViaPartitions "$IMAGE_FILE")
   REAL_FILE_SIZE=$(getFileSize "$IMAGE_FILE")
   if [ "$REAL_FILE_SIZE" -gt "$USED_FILE_SIZE" ]
   then
      if $(questionYesNo "Shrinking \"$IMAGE_FILE\"\nfrom $(toHuman $REAL_FILE_SIZE $BASE)\nto $(toHuman $USED_FILE_SIZE $BASE)?" )
      then
         $DO_VERBOSE && echo "Shrinking \"$IMAGE_FILE\" from $REAL_FILE_SIZE to $USED_FILE_SIZE bytes."
         truncate -c -s $USED_FILE_SIZE "$IMAGE_FILE"
         RET=$?
         [ "$RET" != "0" ] && errorMsg "Unable to resize file \"$IMAGE_FILE\" to $USED_FILE_SIZE bytes!"
      fi
   else
      infoMsg "Nothing to shrink." 3
   fi
fi

exit $RET

#=================================== EOF ======================================
