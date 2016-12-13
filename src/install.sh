#!/bin/bash
###############################################################################
##                                                                           ##
##        Installation- and uninstallation- program for the I-Tools          ##
##                                                                           ##
##---------------------------------------------------------------------------##
## File:     install.sh                                                      ##
## Author:   Ulrich Becker                                                   ##
## Company:  www.INKATRON.de                                                 ##
## Date:     25.09.2014                                                      ##
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
# $Id: install.sh,v 1.6 2014/12/16 10:49:10 uli Exp $
VERSION=0.1
DO_VERBOSE=false
DO_PRINT_HELP=false
DO_LIST_PROGRAMS=false
DO_PRINT_VERSION=false
DO_UNINSTALL=false

PREFIX="/usr/local"

PATH="${PATH}:/sbin:/usr/sbin:/usr/local/bin"

FILE_LIST="dev_permissions irw_common"
FILE_LIST+=" iwrite"
FILE_LIST+=" iread"
FILE_LIST+=" imount"
FILE_LIST+=" cross-chroot"
FILE_LIST+=" iparted"
FILE_LIST+=" rellink"
FILE_LIST+=" xsudo"
FILE_LIST+=" mk-permit"
EXT=".sh"

MUST_BE_INSTALLED="pv dialog Xdialog gparted"

#-------------------------------------------------------------------------------
printHelp()
{
   cat << __EOH__

Program to install or uninstall the INKATRON- I-Tools
$(basename $(readlink -m ${0##*/})): (C) 2014 www.INKATRON.de
Author: Ulrich Becker
Version: $VERSION

Usage: ${0##*/} [-options]

Options:
   -h, --help  This help
   -u          Uninstall
   -l          List all programs.
   -t=<target directory>  Default is "${TARGET_DIR}"
   --version   Print version

__EOH__
}

#------------------------------------------------------------------------------
isPresent()
{
   [ -n "$(which $1 2>/dev/null)" ] && echo true || echo false
}

#------------------------------------------------------------------------------
checkAdditionalInstallations()
{
   local i
   for i in $MUST_BE_INSTALLED
   do
      printf "Check %s\t\t" $i
      if $(isPresent $i)
      then
         printf "installed\n"
      else
         printf "not installed or not found\n"
      fi
   done
}

#------------------------------------------------------------------------------
list()
{
   local i
   for i in $FILE_LIST
   do
      if [ -f "${i}${EXT}" ]
      then
         printf "${i}${EXT}"
         if [ -f "${TARGET_DIR}/${i}${EXT}" ]
         then
            printf "\t\tinstalled"
         else
            printf "\t\t not installed"
         fi
         printf "\n"
      fi
   done
}

#------------------------------------------------------------------------------
installIt()
{
   local i
   for i in $FILE_LIST
   do
      if [ -f "${i}${EXT}" ]
      then
         if [ -f "${TARGET_DIR}/${i}${EXT}" ]
         then
            local a
            read -p "File \"${i}${EXT}\" already exist in \"${TARGET_DIR}\". Overwrite it? [y] " a
            [ "$a" != "y" ] && continue
         fi
         $DO_VERBOSE && echo "INFO: Copy \"${i}${EXT}\" to \"${TARGET_DIR}\""
         cp "${i}${EXT}" "${TARGET_DIR}/" # 2>/dev/null
         if [ "$?" != "0" ]
         then
            echo "ERROR: Unable to copy!" 1>&2
            exit 1
         fi
         if [ -x "${TARGET_DIR}/${i}${EXT}" ]
         then
            $DO_VERBOSE && echo "INFO: Making a symbolic link \"${TARGET_DIR}/${i}${EXT}\" -> \"${TARGET_DIR}/${i}\""
            ln -fs "${TARGET_DIR}/${i}${EXT}" "${TARGET_DIR}/${i}"
         fi
      fi
   done
}

#-----------------------------------------------------------------------------
unInstallIt()
{
   local ret=0
   local i
   for i in $FILE_LIST
   do
      if [ -f "${TARGET_DIR}/${i}${EXT}" ]
      then
         if [ -L "${TARGET_DIR}/${i}" ]
         then
            $DO_VERBOSE && echo "INFO: Remove symbolic link \"${i}\" in directory \"${TARGET_DIR}\""
            rm "${TARGET_DIR}/${i}"
            [ "$?" != "0" ] && ret=1
         fi
         $DO_VERBOSE && echo "INFO: Remove file \"${i}${EXT}\" in directory \"${TARGET_DIR}\""
         rm "${TARGET_DIR}/${i}${EXT}"
         [ "$?" != "0" ] && ret=1
      fi
   done
   return $ret
}

#==============================================================================
TARGET_DIR="${PREFIX}/bin"
MAN_DIR="{$PREFIX}/share/man/man1"

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
         "u")
            DO_UNINSTALL=true
         ;;
         "h")
            DO_PRINT_HELP=true
         ;;
         "l")
            DO_LIST_PROGRAMS=true
         ;;
         "t")
            if [ "${A:1:1}" != "=" ]
            then
               echo "ERROR: Missing \"=\" after option \"${A:0:1}\"!" 1>&2
               ARG_ERROR=true
            else
               TARGET_DIR=${A##*=}
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

if [ ! -d "$TARGET_DIR" ]
then
   echo "ERROR: Target-directory \"$TARGET_DIR\" not found!" 1>&2
   exit 1
fi

if $DO_LIST_PROGRAMS
then
   echo "List of additional installations:"
   checkAdditionalInstallations
   echo
   echo "list of I-Tools in \"$TARGET_DIR\""
   list
   exit 0
fi

if [ $UID -ne 0 ]
then
   echo "Not allow, because you are not root!" 1>&2
   echo "Try: sudo ${0##*/} $ARGS"
   exit 1
fi

if $DO_UNINSTALL
then
   echo "Uninstall"
   unInstallIt
   exit $?
fi

echo "Install!"
installIt

#=================================== EOF ======================================
