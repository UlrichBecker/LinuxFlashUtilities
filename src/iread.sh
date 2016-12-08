#!/bin/bash
###############################################################################
##                                                                           ##
##            Memory to Imagfile reader (SD-Card or CompactFlash)            ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     iread.sh                                                        ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     06.01.2014                                                      ##
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
# $Id: iread.sh,v 1.26 2015/03/18 17:37:25 uli Exp $
VERSION=1.5
BACKTITLE="Image-Reader_$VERSION"
IMAGE_READ_WRITE_MODULE=${0%/*}"/irw_common.sh"

DEFAULT_PV_OPTION="5m"

#------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

Image-reader
(C) 2014 www.INKATRON.de
Author: Ulrich Becker

Usage: ${0##*/} [options] [Target-Image-file] [Source Block-Device]"

If the last Parameter (Source Block-Device) not given and option -x or -d is active,
the source-block-device will be search automatically.
If more then one found of them, a dialogbox will appear with all found connected devices to select.

Block-devices are checked in "$PREMISSION_FILE"

Options:
   -h, --help     This help
   -v             Verbose
   -s, --silence  Silence "dd" is used only
   -d, --dialog   Show progress-bar in a dialog
   -x, --xdialog  Run program in X11 dialog-boxes. Xdialog must be installed.
   -l             List all permitted block-devices of "$PREMISSION_FILE"
   -c             List all connected permitted block-devices of "$PREMISSION_FILE"
   -e, --entire   Copy the entire block-device and not till to the end of the highest partition only.
   -n             No copy (simulate only)
   -Y, --yes      Answers safety questions with "yes".
   -L=<RATE>      Limit the transfer of "pv" to a maximum of RATE bytes per second.
                  A suffix of "k", "m", "g", or "t" can be added to denote kilobytes (*1024),
                  megabytes, and so on. The default is $DEFAULT_PV_OPTION
   --version      Print version and exit.

__EOH__
}

#------------------------------------------------------------------------------
source $IMAGE_READ_WRITE_MODULE
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Module \"${IMAGE_READ_WRITE_MODULE}\" not found!" 1>&2
   exit $RET
fi

if ! $DO_DIALOG && [ $# -lt 1 ]
then
   DIALOG_TEXT="Missing argument(s)!"
   echo "ERROR: $DIALOG_TEXT" 1>&2
   printHelp
   exit 1
fi

SOURCE_ARG=$2
IMAGE_FILE=$1

if [ ! -n "$IMAGE_FILE" ] || [ -d "$IMAGE_FILE" ]
then
   IMAGE_FILE=$(fileMenu "Enter image-filename for target" "$IMAGE_FILE")
   if [ ! -n "$IMAGE_FILE" ]
   then
      echo "Exit by user."
      exit 0
   fi
fi

if [ ! -n "$SOURCE_ARG" ]
then
   searchConnectedPermittedDevice
   SOURCE_ARG=$FOUND_DEVICE
fi

#------------------------------------------------------------------------------
DEVICE_TEXT="Source-device"
exitIfNotPermited "$SOURCE_ARG"
SOURCE_DEVICE=$PERMITTED_DEVICE
if [ ! -e "$SOURCE_DEVICE" ]
then
   DIALOG_TEXT="Source device \"$SOURCE_DEVICE\" not found!"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0 2>/dev/null
   else
      echo "ERROR: $DIALOG_TEXT" 1>&2
   fi
   exit 1
fi

SOURCE_SIZE=$(getFileSize $SOURCE_DEVICE)
if [ "$SOURCE_SIZE" = "0" ]
then
   DIALOG_TEXT="Source-device \"$SOURCE_DEVICE\" possibly not connected!"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0 2>/dev/null
   else
      echo "ERROR: $DIALOG_TEXT" 1>&2
   fi
   exit 1
fi

if [ -b "$IMAGE_FILE" ]
then
   DIALOG_TEXT="Your chosen target \"${IMAGE_FILE}\" is a device-file!"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0 2>/dev/null
   else
      echo "ERROR: $DIALOG_TEXT" 1>&2
   fi
   exit 1
fi

if [ -e "$IMAGE_FILE" ]
then
   DIALOG_TEXT="Target imagefile \"${IMAGE_FILE}\" already exist!\n\nOverwrite it?"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}WARNING" --yesno "$DIALOG_TEXT" 0 0 2>/dev/null
      if [ "$?" != "0" ]
      then
         echo "Exit by user!"
         exit 0
      fi
   else
      printf "WARNING: $DIALOG_TEXT"
      read -p " [y]? " ANSWER
      if [ "$ANSWER" != "y" ]
      then
         echo "Exit by user!"
         exit 0
      fi
   fi
fi


if ! $DO_COPY_TOTAL
then
   $DO_VERBOSE && echo "INFO: Calculating the byte-size to copy. Old size: $SOURCE_SIZE"
   SOURCE_SIZE=$(getSizeViaPartitions "$SOURCE_DEVICE")
   if [ ! -n "$SOURCE_SIZE" ]
   then
      if ! $DO_ALLWAYS_YES
      then
         DIALOG_TEXT="Impossible to calculate the memory-space via partitions!\n"
         DIALOG_TEXT="${DIALOG_TEXT}Copy the entire device?"
         if $DO_DIALOG
         then
            $DIALOG --title "${TITLE_PREFIX}CAUTION" --yesno "$DIALOG_TEXT" 0 0 2>/dev/null
            if [ "$?" != "0" ]
            then
               echo "Exit by user!"
               exit 0
            fi
         else
            printf "$DIALOG_TEXT"
            read -p " [y]? " ANSWER
            if [ "$ANSWER" != "y" ]
            then
               echo "Exit by user!"
               exit 0
            fi
         fi
      fi
      SOURCE_SIZE=$(getFileSize $SOURCE_DEVICE)
   fi
   $DO_VERBOSE && echo "INFO: New size to copy: $SOURCE_SIZE"
fi

#----------------------- ready to copy from flash-drive -----------------------
if ! $DO_ALLWAYS_YES
then
   if $DO_DIALOG
   then
      DIALOG_TEXT="Source device is:     \"${SOURCE_DEVICE}\" $(toHuman $SOURCE_SIZE)\n"
      DIALOG_TEXT="${DIALOG_TEXT}Target image-file is: \"${IMAGE_FILE}\" \n\n"
      DIALOG_TEXT="${DIALOG_TEXT}Are you sure?"
      $DIALOG --title "${TITLE_PREFIX}CAUTION" --yesno "$DIALOG_TEXT" 0 0
      if [ "$?" != "0" ]
      then
         echo "Exit by user!"
         exit 0
      fi
   else
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "Source device is:     \"${SOURCE_DEVICE}\"  $(toHuman $SOURCE_SIZE)"
      echo "Target image-file is: \"${IMAGE_FILE}\""
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      read -p "Are you sure [y]? " ANSWER
      if [ "$ANSWER" != "y" ]
      then
         echo "Exit by user!"
         exit 0
      fi
   fi
fi

#--------------- unmount partitions of flash-drive if mounted -----------------
unmountOrExitIfMounted "$SOURCE_DEVICE"

#------------- unmount the partitions of the image-file if mounted ------------
OLD_MOUNT_POINT=""
if [ -e $IMAGE_FILE ]
then
   if [ -x "$IMAGE_MOUNTER" ]
   then
      OLD_MOUNT_POINT=$($IMAGE_MOUNTER -p $IMOUNT_ARGS $IMAGE_FILE)
      if [ -n "$OLD_MOUNT_POINT" ]
      then
         $DO_VERBOSE && echo "$IMAGE_MOUNTER -u $IMOUNT_ARGS $IMAGE_FILE"
         $IMAGE_MOUNTER -u $IMOUNT_ARGS $IMAGE_FILE
         $DO_VERBOSE && [ -n "$OLD_MOUNT_POINT" ] && echo "INFO: Mountpoint of \"$IMAGE_FILE\" was: \"$OLD_MOUNT_POINT\"."
      fi
   else
      DIALOG_TEXT="Image-mounter/unmounter \"$IMAGE_MOUNTER\" not found!\n\nNevertheless continue?"
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}WARNING" --yesno "$DIALOG_TEXT" 0 0 2>/dev/null
         if [ "$?" != "0" ]
         then
            echo "Exit by user!"
            exit 0
         fi
      else
         printf "WARNING: $DIALOG_TEXT"
         read -p " [y]? " ANSWER
         if [ "$ANSWER" != "y" ]
         then
            echo "Exit by user!"
            exit 1
         fi
      fi
   fi
fi

#--------------------------------- copy ---------------------------------------
BS="1M"
CONV="notrunc,noerror"
RETC="0"
LANG=C

INFOTEXT="Reading $(toHuman $SOURCE_SIZE) of device \"${SOURCE_DEVICE}\" --> \"${IMAGE_FILE}\""
if $(isPresent $PIPE_VIEWER ) && ! $DO_SILENCE
then
   if $DO_DIALOG
   then
      if ! $NO_COPY
      then
         ($PIPE_VIEWER -n -F "%t" -s $SOURCE_SIZE -S  -E ${PV_OPTION} ${SOURCE_DEVICE}  > ${IMAGE_FILE}) 2>&1  |\
         format "$INFOTEXT" |\
         $DIALOG --title "${TITLE_PREFIX}READING" --gauge "$INFOTEXT" 10 80 0
         RETC=$?
      else
         echo $INFOTEXT
         echo "*** Simulating $PIPE_VIEWER via dialog-box. NO COPY! ***"
         echo "($PIPE_VIEWER -n ${PV_OPTION} ${SOURCE_DEVICE} > ${IMAGE_FILE}) 2>&1 |"
         echo "dialog --gauge \"$INFOTEXT\" 10 70 0"
         RETC=$?
      fi
   else
      echo "$INFOTEXT"
      if ! $NO_COPY
      then
         $DO_VERBOSE && echo "$PIPE_VIEWER -tpreb ${PV_OPTION} ${SOURCE_DEVICE} > ${IMAGE_FILE}"
         $PIPE_VIEWER -tpreb -s $SOURCE_SIZE -S -EE ${PV_OPTION} ${SOURCE_DEVICE} > ${IMAGE_FILE}
         RETC=$?
      else
         echo "*** Simulating $PIPE_VIEWER and dd. NO COPY! ***"
         echo "$PIPE_VIEWER -tpreb ${SOURCE_DEVICE} | dd of=${IMAGE_FILE} bs=${BS} conv=${CONV}"
         RETC=$?
      fi
   fi
else
   if ! $DO_SILENCE
   then
      echo "WARNING: No pipe-viewer (program \"${PIPE_VIEWER}\") found!"
      echo "         This will take a while without displaying a progress!"
   fi
   $DO_VERBOSE && echo "$INFOTEXT"
   if ! $NO_COPY
   then
      $DO_VERBOSE && echo "dd count=$SOURCE_SIZE if=${SOURCE_DEVICE} of=${IMAGE_FILE} bs=${BS}"
      dd count=$SOURCE_SIZE if=${SOURCE_DEVICE} of=${IMAGE_FILE} bs=${BS}
      RETC=$?
   else
      echo "*** Simulating dd. NO COPY! ***"
      echo "dd count=$SOURCE_SIZE if=${SOURCE_DEVICE} of=${IMAGE_FILE} bs=${BS}"
      RETC=$?
   fi
fi

#--------------------- remount image-file if was mounted ----------------------
if [ "$RETC" = "0" ]
then
   remount
#------------------------------ ready-message ----------------------------------
   if $DO_DIALOG && ! $DO_ALLWAYS_YES
   then
      DIALOG_TEXT="$(toHuman $SOURCE_SIZE) of \"${SOURCE_DEVICE}\" successful written "
      DIALOG_TEXT="${DIALOG_TEXT}to file \"${IMAGE_FILE}\"."
      $NO_COPY && DIALOG_TEXT="${DIALOG_TEXT} \nSIMULATION!"
      $DIALOG --title "${TITLE_PREFIX}INFO" --msgbox "$DIALOG_TEXT" 0 0
   fi

   $DO_VERBOSE && echo "$(toHuman $SOURCE_SIZE) of \"${SOURCE_DEVICE}\" successful written"\
                       "to device \"${IMAGE_FILE}\" :-)"
   echo "done"
else
   $DO_DIALOG && $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "Returncode = ${RETC}" 0 0
   echo "ERROR: Returncode = $RETC :-(" 1>&2
fi

exit $RETC
#=================================== EOF ======================================

