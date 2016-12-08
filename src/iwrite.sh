#!/bin/bash
###############################################################################
##                                                                           ##
##           ImageFile to Memory burner (SD-Card or CompactFlash)            ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     iwrite.sh                                                       ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     03.01.2014                                                      ##
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
# $Id: iwrite.sh,v 1.36 2015/03/18 17:36:55 uli Exp $
VERSION=1.4
BACKTITLE=("Image-Writer_$VERSION")

IMAGE_READ_WRITE_MODULE=${0%/*}"/irw_common.sh"

DEFAULT_PV_OPTION="5m"

#------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

Image-Writer
Version: $VERSION
(C) 2014 www.INKATRON.de Author: Ulrich Becker

Usage: ${0##*/} [options] [Source-Image-file] [Target Block-Device]
       ${0##*/} <-z | --zero> [options] [Target Block-Device]

If the first parameter not given and option -x or -d is active,
a file-menu will appear.

If the last Parameter (Target Block-Device) not given and option -x or -d is active,
the target-block-device will be search automatically.
If more then one found of them, a dialog-box will appear with all found connected devices to select.

Block-devices are checked in "$PREMISSION_FILE"

Options:
   -h, --help     This help and exit
   -v             Verbose
   -s, --silence  Silence "dd" is used only
   -d, --dialog   Run program in dialog-boxes
   -x, --xdialog  Run program in X11 dialog-boxes. Xdialog must be installed.
   -l             List all permitted block-devices of "$PREMISSION_FILE"
   -c             List all connected permitted block-devices of "$PREMISSION_FILE"
   -e, --entire   Copy the entire file-size and not till to the end of the highest partition only.
   -n             No copy (simulate only)
   -Y, --yes      Answers safety questions with "yes".
   -z, --zero     Clear the content of entire target device by /dev/zero

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

if [ $# -lt 1 ] && ! $DO_DIALOG
then
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "Missing argument(s)!" 0 0 2>/dev/null
   else
      echo "ERROR: Missing argument(s)!" 1>&2
      printHelp
   fi
   exit 1
fi

if $DO_CLEAR_TARGET
then
   TARGET_ARG=$1
   IMAGE_FILE="/dev/zero"
   IMAGE_IS_A_DEVICE=true
else
   TARGET_ARG=$2
   IMAGE_FILE=$1
fi

if ! $DO_CLEAR_TARGET
then
   if ( [ ! -n "$IMAGE_FILE" ] || [ -d "$IMAGE_FILE" ] )
   then
      if $DO_DIALOG
      then
         IMAGE_FILE=$(fileMenu "Select a image-file" "$IMAGE_FILE" )
         if [ ! -n "$IMAGE_FILE" ]
         then
            echo "Exit by user."
            exit 0
         fi
         if [ ! -f "$IMAGE_FILE" ]
         then
            $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "\"$IMAGE_FILE\" is not a valid file!" 0 0
            exit 1
         fi
      else
         echo "ERROR: No valid image-file: \"$IMAGE_FILE\"" 1>&2
         exit 1
      fi
   fi
   SOURCE_SIZE=$(getFileSize $IMAGE_FILE)
   if ! $DO_COPY_TOTAL
   then
      $DO_VERBOSE && echo "INFO: Calculating the byte-size to copy. Old size: $SOURCE_SIZE"
      SOURCE_SIZE=$(getSizeViaPartitions "$IMAGE_FILE")
      if [ -n "$SOURCE_SIZE" ]
      then
         $DO_VERBOSE && echo "INFO: New size to copy: $SOURCE_SIZE"
      else
         SOURCE_SIZE=$(getFileSize $IMAGE_FILE)
         if $DO_DIALOG
         then
            $DIALOG --title "${TITLE_PREFIX}WARNING" --msgbox "Impossible to calculate the size via partitions!" 0 0
         else
            echo "WARNING: Impossible to calculate the size via partitions!" 1>&2
         fi
      fi
   fi
fi

if [ ! -n "$TARGET_ARG" ]
then
   searchConnectedPermittedDevice "$SOURCE_SIZE"
   TARGET_ARG=$FOUND_DEVICE
fi

#env "TARGET_ARG=$TARGET_ARG" 1>/dev/null

#------------------------------------------------------------------------------
DEVICE_TEXT="Target-device"
exitIfNotPermited "$TARGET_ARG"
TARGET_DEVICE=$(readlink -m "$PERMITTED_DEVICE")

# IMAGE_FILE=$(readlink -m $IMAGE_FILE)


#---------------------------- test of image-file ------------------------------
if ! $DO_CLEAR_TARGET
   then
      if [ ! -s $IMAGE_FILE ] && [ ! -b $IMAGE_FILE ]
      then
      DIALOG_TEXT="Can't find image-file: \"$IMAGE_FILE\" or invalid!"
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0
      else
         echo "ERROR: $DIALOG_TEXT" 1>&2
      fi
      exit 1
   fi

   if [ -b $IMAGE_FILE ]
   then
      DEVICE_TEXT="Source-device"
      exitIfNotPermited "$IMAGE_FILE"
      IMAGE_FILE=$PERMITED_DEVICE

      if [ "$IMAGE_FILE" = "$TARGET_DEVICE" ]
      then
         DIALOG_TEXT="Source and target are the same: \"$IMAGE_FILE\"!"
         if $DO_DIALOG
         then
            $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0
         else
            echo "ERROR $DIALOG_TEXT" 1>&2
         fi
         exit 1
      fi
      IMAGE_IS_A_DEVICE=true
   else
      IMAGE_IS_A_DEVICE=false
      if ! $DO_ALLWAYS_YES
      then
         checkImageFile $IMAGE_FILE
         if [ "$PARTITIONS" != "0" ]
         then
            $DO_VERBOSE && echo "INFO: $PARTITIONS partitions found in \"$IMAGE_FILE\""
            if [ "$BOOT_PART" != "0" ]
            then
               $DO_VERBOSE && echo "INFO: $BOOT_PART boot-partition found in \"$IMAGE_FILE\""
            else
               DIALOG_TEXT="No boot-partition found in \n\"$IMAGE_FILE\"! \n\nNevertheless copy?"
               if $DO_DIALOG
               then
                  $DIALOG --title "${TITLE_PREFIX}WARNING" --yesno "$DIALOG_TEXT" 0 0
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
         else
            DIALOG_TEXT="No partitions found in\n\"$IMAGE_FILE\"! \n\nNevertheless copy?"
            if $DO_DIALOG
            then
               $DIALOG --title "${TITLE_PREFIX}WARNING" --yesno "$DIALOG_TEXT" 0 0
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
      fi
   fi
fi

#-------------------------- check target and source sizes ---------------------
TARGET_SIZE=$(getFileSize $TARGET_DEVICE)
if [ "$TARGET_SIZE" = "0" ]
then
   DIALOG_TEXT="Device \"$TARGET_DEVICE\" possibly not connected!"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0
   else
      echo "ERROR: $DIALOG_TEXT" 1>&2
   fi
   exit 1
fi

if $DO_CLEAR_TARGET
then
   SOURCE_SIZE=$TARGET_SIZE
else
   if [ "$SOURCE_SIZE" -gt "$TARGET_SIZE" ]
   then
      ERROR_TEXT="Size of source \"${IMAGE_FILE}\" is greater then\nthe maximum size of target \"${TARGET_DEVICE}\"! \n\n"
      ERROR_TEXT="${ERROR_TEXT}       Source: $(toHuman $SOURCE_SIZE)\n"
      ERROR_TEXT="${ERROR_TEXT}       Target: $(toHuman $TARGET_SIZE)"
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$ERROR_TEXT" 0 0
      else
         printf "ERROR: ${ERROR_TEXT}\n\n" 1>&2
      fi
      exit 1
   fi
fi

#----------------------- ready to burn the flash-drive ------------------------
if ! $DO_ALLWAYS_YES
then
   if $DO_DIALOG
   then
      if $DO_CLEAR_TARGET
      then
         DIALOGTEXT="Ready to clear the target of $(toHuman $TARGET_SIZE).\n"
      else
         DIALOGTEXT="Ready to write $(toHuman $SOURCE_SIZE) \nto a target of $(toHuman $TARGET_SIZE).\n"
      fi
      if $IMAGE_IS_A_DEVICE
      then
         DIALOGTEXT="${DIALOGTEXT}Source-device is:     \"${IMAGE_FILE}\"\n"
      else
         DIALOGTEXT="${DIALOGTEXT}Source-image-file is: \"${IMAGE_FILE}\"\n"
      fi
      DIALOGTEXT="${DIALOGTEXT}Target-device is:     \"${TARGET_DEVICE}\"\n"
      DIALOGTEXT="${DIALOGTEXT}\nAre you sure?"
      $DIALOG --title "${TITLE_PREFIX}CAUTION" --yesno "$DIALOGTEXT" 0 0
      if [ "$?" != "0" ]
      then
         echo "Exit by user!"
         exit 0
      fi
   else
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      if $DO_CLEAR_TARGET
      then
         echo "Ready to clear the target of $(toHuman $TARGET_SIZE)."
      else
         echo "Ready to write $(toHuman $SOURCE_SIZE) to a target of $(toHuman $TARGET_SIZE)."
      fi
      if $IMAGE_IS_A_DEVICE
      then
         echo "Source-device is:        \"${IMAGE_FILE}\""
      else
         echo "Source-image-file is:    \"${IMAGE_FILE}\""
      fi
      echo "Target-device is:        \"${TARGET_DEVICE}\""
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
unmountOrExitIfMounted "$TARGET_DEVICE"

#----------------------------- write-test -------------------------------------
if ! $NO_COPY
then
   LANG=C
   if [ -n "$(dd bs=16 count=0 if=/dev/zero of="${TARGET_DEVICE}" 2>&1 | awk -F : '{printf $3}' | grep "Read-only")" ]
   then
      DIALOG_TEXT="Targetdevice \"${TARGET_DEVICE}\" is read-only!"
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0
      else
         echo "ERROR: $DIALOG_TEXT" 1>&2
      fi
      exit 1
   fi
elif $DO_VERBOSE
then
    echo "INFO: write-test not possible in test-mode."
fi

#------------- unmount the partitions of the image-file if mounted ------------
OLD_MOUNT_POINT=""
if ! $DO_CLEAR_TARGET
then
   if $IMAGE_IS_A_DEVICE
   then
      unmountOrExitIfMounted $IMAGE_FILE
   else
      if [ -x "$IMAGE_MOUNTER" ]
      then
         OLD_MOUNT_POINT=$($IMAGE_MOUNTER -p $IMOUNT_ARGS $IMAGE_FILE)
         if [ -n $OLD_MOUNT_POINT ]
         then
            $DO_VERBOSE && echo "$IMAGE_MOUNTER -u $IMOUNT_ARGS $IMAGE_FILE"
            $IMAGE_MOUNTER -u $IMOUNT_ARGS $IMAGE_FILE
            $DO_VERBOSE && echo "INFO: Mountpoint of \"$IMAGE_FILE\" was: \"$OLD_MOUNT_POINT\"."
         fi
      elif $DO_DIALOG
      then
         $DIALOG --yesno "${TITLE_PREFIX}WARNING: Image-mounter/unmounter \"$IMAGE_MOUNTER\" \nnot found! \n\nNevertheless continue?" 10 60
         if [ "$?" != "0" ]
         then
            echo "Exit by user!"
            exit 0
         fi
      else
         echo "WARNING: Image-mounter/unmounter \"$IMAGE_MOUNTER\" not found!"
         read -p "Nevertheless continue? [y] " ANSWER
         if [ "$ANSWER" != "y" ]
         then
            echo "Exit by user!"
            exit 0
         fi
      fi
   fi
fi

#--------------------------------- copy ---------------------------------------
BS="1M"
CONV="notrunc,noerror"
RETC="0"

if $DO_CLEAR_TARGET
then
   INFOTEXT="Clearing the entire device: \"${TARGET_DEVICE}\""
else
   INFOTEXT="Writing $(toHuman $SOURCE_SIZE) of image: \"${IMAGE_FILE}\" --> \"${TARGET_DEVICE}\""
fi

TIME=$(date +%s)

if [ -n "$PIPE_VIEWER" ] && ! $DO_SILENCE
then
   if $DO_DIALOG
   then
      if ! $NO_COPY
      then
         ($PIPE_VIEWER  -n -F "%t" -s $SOURCE_SIZE -S ${PV_OPTION} ${IMAGE_FILE} > ${TARGET_DEVICE}) 2>&1 |\
         format "$INFOTEXT" |\
         $DIALOG --title "${TITLE_PREFIX}WRITING" --gauge "$INFOTEXT" 10 80 0
         RETC=$?
      else
         echo $INFOTEXT
         echo "*** Simulating $PIPE_VIEWER and dd via dialog-box. NO COPY! ***"
         echo "($PIPE_VIEWER -n ${PV_OPTION} ${IMAGE_FILE} > ${TARGET_DEVICE}) 2>&1 |"
         echo "dialog --gauge \"$INFOTEXT\" 10 70 0"
         RETC=$?
      fi
   else
      echo "$INFOTEXT"
      if ! $NO_COPY
      then
         $DO_VERBOSE && echo "$PIPE_VIEWER -tpreb ${IMAGE_FILE} | dd of=${TARGET_DEVICE} bs=${BS} conv=${CONV}"
        # $PIPE_VIEWER -tpreb ${PV_OPTION} ${IMAGE_FILE} | dd of=${TARGET_DEVICE} bs=${BS} conv=${CONV}
         $PIPE_VIEWER -tpreb -s $SOURCE_SIZE -S ${PV_OPTION} ${IMAGE_FILE} > ${TARGET_DEVICE}
         RETC=$?
      else
         echo "*** Simulating $PIPE_VIEWER and dd. NO COPY! ***"
         echo "$PIPE_VIEWER -tpreb ${PV_OPTION} ${IMAGE_FILE}  > ${TARGET_DEVICE}"
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
      $DO_VERBOSE && echo "dd count=$SOURCE_SIZE if=${IMAGE_FILE} of=${TARGET_DEVICE} bs=${BS}"
      dd count=$SOURCE_SIZE if=${IMAGE_FILE} of=${TARGET_DEVICE} bs=${BS}
      RETC=$?
   else
      echo "*** Simulating dd. NO COPY! ***"
      echo "dd count=$SOURCE_SIZE if=${IMAGE_FILE} of=${TARGET_DEVICE} bs=${BS}"
      RETC=$?
   fi
fi
TIME=$(($(date +%s) - $TIME))

#--------------------- remount image-file if was mounted ----------------------
$DO_CLEAR_TARGET || remount

#------------------------------ ready-message ----------------------------------
if [ $RETC = "0" ]
then
   if $DO_DIALOG && ! $DO_ALLWAYS_YES
   then
      if $DO_CLEAR_TARGET
      then
         DIALOG_TEXT="\"${TARGET_DEVICE}\" successful cleared \n"
      else
         DIALOG_TEXT="$(toHuman $SOURCE_SIZE) of \"${IMAGE_FILE}\" successful written \n" #\
         DIALOG_TEXT="${DIALOG_TEXT}to device \"${TARGET_DEVICE}\".\n"
      fi
      DIALOG_TEXT="${DIALOG_TEXT}Elapsed time: $(seconds2timeFormat $TIME)"
      $NO_COPY && DIALOG_TEXT="${DIALOG_TEXT} \nSIMULATION!"
      $DIALOG --title "${TITLE_PREFIX}INFO" --msgbox "$DIALOG_TEXT" 0 0
   fi
   if $DO_VERBOSE
   then
      if $DO_CLEAR_TARGET
      then
         echo "\"${TARGET_DEVICE}\" successfull cleared!"
      else
         echo "$(toHuman $SOURCE_SIZE) of \"${IMAGE_FILE}\" successful written"\
                          "to device \"${TARGET_DEVICE}\" :-)"
      fi
      echo "Elapsed time: $(seconds2timeFormat $TIME)"
   fi
   echo "done"
else
   $DO_DIALOG && $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "Returncode = ${RETC}" 0 0
   echo "ERROR: Returncode = $RETC :-(" 1>&2
fi

exit $RETC
#=================================== EOF ======================================
