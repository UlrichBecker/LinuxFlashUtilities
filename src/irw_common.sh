###############################################################################
##                                                                           ##
##                Shared-Module for iwrite.sh and iread.sh                   ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     irw_common.sh                                                   ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     27.01.2014                                                      ##
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
# $Id: irw_common.sh,v 1.33 2015/03/18 17:37:25 uli Exp $


USE_DIALOG=false
IMAGE_MOUNTER="${0%/*}/imount.sh"
PERMISSION_MODULE="${0%/*}/dev_permissions.sh"
RC_FILE="${0%/*}/irc.rc"

PIPE_VIEWER="pv"
MIN_PV_VERSION="1.5.7"
PATH="./:/sbin:/usr/local/bin/:${PATH}"
DO_VERBOSE=false
DO_DIALOG=false
DO_SILENCE=false
DO_LIST_PERMISSIONS=false
DO_LIST_FOUND_PERMISSIONS=false
DO_PRINT_HELP=false
DO_PRINT_VERSION=false
DO_COPY_TOTAL=false
NO_COPY=false
DO_ALLWAYS_YES=false
DO_CLEAR_TARGET=false

PV_OPTION="-L $DEFAULT_PV_OPTION"

IMOUNT_ARGS=""

FOUND_DEVICE=""

T_DIALOG=dialog
X_DIALOG=Xdialog
DIALOG=$T_DIALOG
TITLE_PREFIX="${0##*/}: "

source $PERMISSION_MODULE
RET=$?
if [ "$RET" != "0" ]
then
   echo "ERROR: Module \"${PERMISSION_MODULE}\" not found!" 1>&2
   exit $RET
fi

#------------------------------------------------------------------------------
getFileSizeInfo()
{
   ls -L -sh "$1"
}

#------------------------------------------------------------------------------
checkImageFile()
{
   LANG=C
   local buffer=$(fdisk -lu "$1" | tr '*' 'X' | grep "$1[a-z0-9]")

   PARTITIONS="0"
   BOOT_PART="0"
   for i in $buffer
   do
      case $i in
         $1[a-z0-9])
            ((PARTITIONS++))
         ;;
         'X')
            ((BOOT_PART++))
         ;;
      esac
   done
}

#------------------------------------------------------------------------------
exitIfNotPermited()
{
   local errorText=$(checkPermissions "$1" 2>&1)
   if [ -n "$errorText" ]
   then
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$errorText" 0 0
      else
         echo "ERROR: $errorText" 1>&2
      fi
      exit 1
   fi

   PERMITTED_DEVICE=$(getBlockDeviceName "$1")
}

#------------------------------------------------------------------------------
trunc()
{
   i=${1%.*}
   i=${i%,*}
   echo $i
}

#------------------------------------------------------------------------------
seconds2timeFormat()
{
   local time=$1
   local seconds=$(($time % 60))
   time=$(( $(($time - $seconds)) / 60 ))
   local minutes=$(($time % 60))
   time=$(( $(($time - $minutes)) / 60 ))
   local hours=$(($time % 60))

   printf "%01d:%02d:%02d" ${hours} ${minutes} ${seconds}
}

#------------------------------------------------------------------------------
format()
{
   local text="$1"
   local t
   local p
   local prevP=0
   while read t p
   do
     echo "XXX"
     t=$(trunc $t)
     printf "%s\r\nElapsed time: %s\r\n" "$text" "$(seconds2timeFormat $t)"
     if [ "$p" -ge "1" ]
     then
        if [ "$p" = "100" ]
        then
           printf "Please, still wait a little bit till the buffer is empty.\r\n"
        else
           if [ "$prevP" != "$p" ]
           then
              prevP=$p
              local tTotal=$(( $t * 100 / $p ))
           fi
           printf "Estimated remaining time: %s\r\n" "$(seconds2timeFormat $(($tTotal - $t)) )"
        fi
     fi
     echo "XXX"
     echo "$p"
   done
}

#-------------------------------------------------------------------------------
searchConnectedPermittedDevice()
{
   DO_ALLWAYS_YES=false
   FOUND_DEVICE=""
   local n=$(getNumberOfFoundPermitedAppropriateDevices "$1" )

   if [ "$n" = "0" ]
   then
      DIALOG_TEXT="No connected block-device found!"
      if $DO_DIALOG
      then
         $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0
      else
         echo "ERROR: $DIALOG_TEXT" 1>&2
      fi
      exit 1
   fi

   FOUND_DEVICE=$(listFuondPermitedDevices "$1" )
   if [ "$n" = "1" ]
   then
      FOUND_DEVICE=${FOUND_DEVICE%%' '*}
      return 0
   fi

   if $DO_DIALOG
   then
      local devSelectDialog=($DIALOG --title "${TITLE_PREFIX}Select" --menu "$n connected block-devices found:" 0 50 $n)
      local c=0
      local i
      local items
      local IFS=$'\n'
      for i in $FOUND_DEVICE
      do
        items+=($((++c)) "$i")
      done

      local selected=$("${devSelectDialog[@]}" "${items[@]}" 3>&1 1>&2 2>&3)
      selected=${selected##*[!0-9]}
      $DO_VERBOSE && echo "INFO: Selected number: $selected"
      if [ ! -n "$selected" ]
      then
         echo "Exit by user!"
         exit 0
      fi

      n=0
      local i
      local IFS=$'\n'
      for i in $FOUND_DEVICE
      do
         ((n++))
         if [ "$n" = "$selected" ]
         then
            FOUND_DEVICE=${i%%' '*}
            return 0
         fi
      done
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "Wrong selection: \"$selected\"" 0 0
      exit 1
   else
      echo "ERROR: More then one device found!" 1>&2
      #TODO Selection without dialogbox.
      exit 1
   fi
   FOUND_DEVICE=""
}

#------------------------------------------------------------------------------
fileMenu()
{
   local sFile

   [ -n "$2" ] && sFile="$2" || sFile="$(pwd)"

   while [ -d "$sFile" ]
   do
      sFile="$(readlink -m "$sFile")"
      sFile=$(echo $($DIALOG --title "${TITLE_PREFIX}$1" --fselect "$sFile/" 0 0 3>&1 1>&2 2>&3 ))
      sFile=${sFile##* }
   done
   echo "$sFile"
}

#------------------------------------------------------------------------------
unmountOrExitIfMounted()
{
   if [ -n "$(mount | grep  "$1")" ]
   then
      if ! $DO_ALLWAYS_YES
      then
         DIALOG_TEXT="Device \"$1\" is mounted! \nUnmount it?"
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
            local answer
            read -p " [y] " answer
            if [ "$answer" != "y" ]
            then
               echo "Exit by user!"
               exit 0
            fi
         fi
      fi
      unmountMemoryDevice "$1"
   fi
}

#------------------------------------------------------------------------------
remount()
{
   if [ -n "$OLD_MOUNT_POINT" ]
   then
      if $DO_VERBOSE
      then
         echo "INFO: Remount unmounted image-file: \"${IMAGE_FILE}\" on mountpoint \"${OLD_MOUNT_POINT}\"."
         echo "$IMAGE_MOUNTER $IMOUNT_ARGS $IMAGE_FILE $OLD_MOUNT_POINT"
      fi
      $IMAGE_MOUNTER $IMOUNT_ARGS $IMAGE_FILE $OLD_MOUNT_POINT
   fi
}

#------------------------------------------------------------------------------
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
            IMOUNT_ARGS="-v"
        ;;
        "s")
            DO_SILENCE=true
        ;;
        "d")
            DO_DIALOG=true
        ;;
        "x")
            DO_DIALOG=true
            DIALOG=$X_DIALOG
        ;;
        "l")
            DO_LIST_PERMISSIONS=true
        ;;
        "c")
            DO_LIST_FOUND_PERMISSIONS=true
        ;;
        "n")
            NO_COPY=true
        ;;
        "e")
            DO_COPY_TOTAL=true
        ;;
        "z")
            DO_CLEAR_TARGET=true
        ;;
        "Y")
            DO_ALLWAYS_YES=true
        ;;
        "L")
            if [ "${A:1:1}" != "=" ]
            then
               echo "ERROR: Missing \"=\" after option \"${A:0:1}\"!" 1>&2
               ARG_ERROR=true
            else
               PV_OPTION="-L ${A##*=}"
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
               "silence")
                  DO_SILENCE=true
               ;;
               "dialog")
                  DO_DIALOG=true
               ;;
               "xdialog")
                  DO_DIALOG=true
                  DIALOG=$X_DIALOG
               ;;
               "yes")
                  DO_ALLWAYS_YES=true
               ;;
               "entire")
                  DO_COPY_TOTAL=true
               ;;
               "zero")
                  DO_CLEAR_TARGET=true
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
   exit 0$SSTR
fi

if $DO_DIALOG
then
   if [ "$DIALOG" = "$X_DIALOG" ]
   then
      if ! $(isPresent "$X_DIALOG")
      then
         DIALOG=$T_DIALOG
         $DIALOG --title "${TITLE_PREFIX}WARNING" --msgbox \
         "\"$X_DIALOG\" not found or possibly not installed! \nFalling back to \"$DIALOG\"." 0 0 2>/dev/null
      elif [ ! -n "$DISPLAY" ]
      then
         DIALOG=$T_DIALOG
      fi
   fi

   if ! $DO_SILENCE && ! $(isPresent "$PIPE_VIEWER")
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox \
      "Pipe-viewer \"$PIPE_VIEWER\" not found or possibly not installed!" 0 0 2>/dev/null
      exit 1
   fi
fi

if [ "$DIALOG" = "$X_DIALOG" ]
then
   DIALOG="$X_DIALOG --rc-file $RC_FILE --fixed-font --left "
   export XDIALOG_HIGH_DIALOG_COMPAT=false
   export XDIALOG_FORCE_AUTOSIZE=true
fi

$DO_DIALOG && [ -n "$BACKTITLE" ] && DIALOG+=" --backtitle ${BACKTITLE[@]}"

if $DO_PRINT_HELP
then
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}HELP" --msgbox "$(printHelp)" 0 0 2>/dev/null
   else
      printHelp
   fi
   if ! $DO_LIST_PERMISSIONS
   then
      exit 0
   fi
fi

if $(isPresent "$PIPE_VIEWER") && ! $DO_SILENCE
then
   PV_VERSION="$($PIPE_VIEWER --version | awk -F '\n' '{printf $1}' | awk '{printf $2}' )"
   if [ "$PV_VERSION" \< "$MIN_PV_VERSION" ]
   then
      DIALOG_TEXT="Pipeviewer \"$PIPE_VIEWER\" version $MIN_PV_VERSION is necessary!\nInstalled version is $PV_VERSION"
      if $DO_DIALOG
      then
          $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT"  0 0 2>/dev/null
      else
          printf "ERROR: $DIALOG_TEXT" 1>&2
      fi
      exit 1
   fi
else
   PIPE_VIEWER=""
fi

if [ ! -s "$PREMISSION_FILE" ]
then
   DIALOG_TEXT="Permission-list \"${PREMISSION_FILE}\" not found or invalid!"
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "$DIALOG_TEXT" 0 0 2>/dev/null
   else
      echo "ERROR: $DIALOG_TEXT" 1>&2
   fi
   exit 1
fi

if $DO_LIST_PERMISSIONS
then
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}Permissions" --msgbox "$(listPermissions 2>&1)" 0 0 2>/dev/null
   else
      $DO_VERBOSE && echo "INFO: Permitted devices:"
      listPermissions
   fi
   exit $?
fi

if $DO_LIST_FOUND_PERMISSIONS
then
   if $DO_DIALOG
   then
      $DIALOG --title "${TITLE_PREFIX}Found permitted device(s)" --msgbox "$(listFuondPermitedDevices 2>&1)" 0 0 2>/dev/null
   else
      $DO_VERBOSE && echo "INFO: Found permitted devices:"
      listFuondPermitedDevices
   fi
   exit $?
fi

if [ $UID -ne 0 ]
then
   if $DO_DIALOG
   then
       $DIALOG --title "${TITLE_PREFIX}ERROR" --msgbox "Not allow, because you are not root! \nTry: xsudo ${0##*/}" 0 0 2>/dev/null
   else
      echo "ERROR: Not allow, because you are not root!" 1>&2
      echo "       Try: sudo ${0##*/} $@" 1>&2
   fi
   exit 1
fi

#=================================== EOF ======================================
