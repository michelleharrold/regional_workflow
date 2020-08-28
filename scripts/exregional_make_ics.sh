#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHDIR/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u +x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that generates initial condition
(IC), surface, and zeroth hour lateral boundary condition (LBC0) files
for FV3 (in NetCDF format).
========================================================================"
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.  Then
# process the arguments provided to this script/function (which should
# consist of a set of name-value pairs of the form arg1="value1", etc).
#
#-----------------------------------------------------------------------
#
valid_args=( \
"wgrib2_dir" \
"ics_dir" \
"APRUN" \
)
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
# Source the file containing definitions of variables associated with the
# external model for ICs.
#
#-----------------------------------------------------------------------
#
extrn_mdl_staging_dir="${CYCLE_DIR}/${EXTRN_MDL_NAME_ICS}/for_ICS"
extrn_mdl_var_defns_fp="${extrn_mdl_staging_dir}/${EXTRN_MDL_ICS_VAR_DEFNS_FN}"
. ${extrn_mdl_var_defns_fp}
#
#-----------------------------------------------------------------------
#
#
#
#-----------------------------------------------------------------------
#
workdir="${ics_dir}/tmp_ICS"
mkdir_vrfy -p "$workdir"
cd_vrfy $workdir
#
#-----------------------------------------------------------------------
#
# Set physics-suite-dependent variables that are needed in the FORTRAN
# namelist file that the chgres executable will read in.
#
#-----------------------------------------------------------------------
#
phys_suite=""

case "${CCPP_PHYS_SUITE}" in

"FV3_GFS_2017_gfdlmp" | "FV3_GFS_2017_gfdlmp_regional" )
  phys_suite="GFS"
  ;;
"FV3_GSD_v0" | "FV3_GSD_SAR" | "FV3_GSD_SAR_v1" |"FV3_RRFS_v0" |"FV3_RRFS_v1beta")
  phys_suite="GSD"
  ;;
"FV3_CPT_v0")
  phys_suite="CPT"
  ;;
"FV3_GFS_v15p2")
  phys_suite="v15p2"
  ;;
"FV3_GFS_v16beta")
  phys_suite="v16beta"
  ;;
*)
  print_err_msg_exit "\
Physics-suite-dependent namelist variables have not yet been specified
for this physics suite:
  CCPP_PHYS_SUITE = \"${CCPP_PHYS_SUITE}\""
  ;;

esac
#
#-----------------------------------------------------------------------
#
# Set external-model-dependent variables that are needed in the FORTRAN
# namelist file that the chgres executable will read in.  These are de-
# scribed below.  Note that for a given external model, usually only a
# subset of these all variables are set (since some may be irrelevant).
#
# external_model:
# Name of the external model from which we are obtaining the fields
# needed to generate the ICs.
#
# fn_atm_nemsio:
# Name (not including path) of the nemsio file generated by the external
# model that contains the atmospheric fields.
#
# fn_sfc_nemsio:
# Name (not including path) of the nemsio file generated by the external
# model that contains the surface fields.
#
# input_type:
# The "type" of input being provided to chgres.  This contains a combi-
# nation of information on the external model, external model file for-
# mat, and maybe other parameters.  For clarity, it would be best to
# eliminate this variable in chgres and replace with with 2 or 3 others
# (e.g. extrn_mdl, extrn_mdl_file_format, etc).
#
# tracers_input:
# List of atmospheric tracers to read in from the external model file
# containing these tracers.
#
# tracers:
# Names to use in the output NetCDF file for the atmospheric tracers
# specified in tracers_input.  With the possible exception of GSD phys-
# ics, the elements of this array should have a one-to-one correspond-
# ence with the elements in tracers_input, e.g. if the third element of
# tracers_input is the name of the O3 mixing ratio, then the third ele-
# ment of tracers should be the name to use for the O3 mixing ratio in
# the output file.  For GSD physics, three additional tracers -- ice,
# rain, and water number concentrations -- may be specified at the end
# of tracers, and these will be calculated by chgres.
#
# internal_GSD:
# Logical variable indicating whether or not to try to read in land sur-
# face model (LSM) variables available in the HRRRX grib2 files created
# after about 2019111500.
#
# numsoil_out:
# The number of soil layers to include in the output NetCDF file.
#
# replace_FIELD, where FIELD="vgtyp", "sotyp", or "vgfrc":
# Logical variable indicating whether or not to obtain the field in
# question from climatology instead of the external model.  The field in
# question is one of vegetation type (FIELD="vgtyp"), soil type (FIELD=
# "sotyp"), and vegetation fraction (FIELD="vgfrc").  If replace_FIELD
# is set to ".true.", then the field is obtained from climatology (re-
# gardless of whether or not it exists in an external model file).  If
# it is set to ".false.", then the field is obtained from the external
# model.  If the external model file does not provide this field, then
# chgres prints out an error message and stops.
#
# tg3_from_soil:
# Logical variable indicating whether or not to set the tg3 soil tempe-  # Needs to be verified.
# rature field to the temperature of the deepest soil layer.
#
#-----------------------------------------------------------------------
#

# GSK comments about chgres:
#
# The following are the three atmsopheric tracers that are in the atmo-
# spheric analysis (atmanl) nemsio file for CDATE=2017100700:
#
#   "spfh","o3mr","clwmr"
#
# Note also that these are hardcoded in the code (file input_data.F90,
# subroutine read_input_atm_gfs_spectral_file), so that subroutine will
# break if tracers_input(:) is not specified as above.
#
# Note that there are other fields too ["hgt" (surface height (togography?)),
# pres (surface pressure), ugrd, vgrd, and tmp (temperature)] in the atmanl file, but those
# are not considered tracers (they're categorized as dynamics variables,
# I guess).
#
# Another note:  The way things are set up now, tracers_input(:) and
# tracers(:) are assumed to have the same number of elements (just the
# atmospheric tracer names in the input and output files may be differ-
# ent).  There needs to be a check for this in the chgres_cube code!!
# If there was a varmap table that specifies how to handle missing
# fields, that would solve this problem.
#
# Also, it seems like the order of tracers in tracers_input(:) and
# tracers(:) must match, e.g. if ozone mixing ratio is 3rd in
# tracers_input(:), it must also be 3rd in tracers(:).  How can this be checked?
#
# NOTE: Really should use a varmap table for GFS, just like we do for
# RAP/HRRR.
#
# A non-prognostic variable that appears in the field_table for GSD physics
# is cld_amt.  Why is that in the field_table at all (since it is a non-
# prognostic field), and how should we handle it here??

# I guess this works for FV3GFS but not for the spectral GFS since these
# variables won't exist in the spectral GFS atmanl files.
#  tracers_input="\"sphum\",\"liq_wat\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\",\"o3mr\""
#
# Not sure if tracers(:) should include "cld_amt" since that is also in
# the field_table for CDATE=2017100700 but is a non-prognostic variable.

external_model=""
fn_atm_nemsio=""
fn_sfc_nemsio=""
fn_grib2=""
input_type=""
tracers_input="\"\""
tracers="\"\""
internal_GSD=""
numsoil_out=""
geogrid_file_input_grid="\"\""
replace_vgtyp=""
replace_sotyp=""
replace_vgfrc=""
tg3_from_soil=""
convert_nst=""


case "${EXTRN_MDL_NAME_ICS}" in


"GSMGFS")

  external_model="GSMGFS"

  fn_atm_nemsio="${EXTRN_MDL_FNS[0]}"
  fn_sfc_nemsio="${EXTRN_MDL_FNS[1]}"
  input_type="gfs_gaussian" # For spectral GFS Gaussian grid in nemsio format.

  tracers_input="[\"spfh\",\"clwmr\",\"o3mr\"]"
  tracers="[\"sphum\",\"liq_wat\",\"o3mr\"]"

  internal_GSD=False
  numsoil_out="4"
  replace_vgtyp=True
  replace_sotyp=True
  replace_vgfrc=True
  tg3_from_soil=False
  convert_nst=False

  ;;


"FV3GFS")

  if [ "${FV3GFS_FILE_FMT_ICS}" = "nemsio" ]; then

    external_model="FV3GFS"

    fn_atm_nemsio="${EXTRN_MDL_FNS[0]}"
    fn_sfc_nemsio="${EXTRN_MDL_FNS[1]}"
    input_type="gaussian"     # For FV3-GFS Gaussian grid in nemsio format.

    tracers_input="[\"spfh\",\"clwmr\",\"o3mr\",\"icmr\",\"rwmr\",\"snmr\",\"grle\"]"

#
# If CCPP is being used, then the list of atmospheric tracers to include
# in the output file depends on the physics suite.  Hopefully, this me-
# thod of specifying output tracers will be replaced with a variable
# table (which should be specific to each combination of external model,
# external model file type, and physics suite).
#
    if [ "${USE_CCPP}" = "TRUE" ]; then
      if [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp_regional" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_CPT_v0" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v15p2" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v16beta" ]; then
        tracers="[\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\"]"
      elif [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR_v1" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v0" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v1beta" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ]; then
# For GSD physics, add three additional tracers (the ice, rain and water
# number concentrations) that are required for Thompson microphysics.
        tracers="[\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\",\"ice_nc\",\"rain_nc\",\"water_nc\"]"
      else
        print_err_msg_exit "\
The parameter \"tracers\" has not been defined for this combination of 
external model (EXTRN_MDL_NAME_ICS), physics suite (CCPP_PHYS_SUITE), and 
FV3GFS file type (FV3GFS_FILE_FMT_ICS):
  EXTRN_MDL_NAME_ICS = \"${EXTRN_MDL_NAME_ICS}\"
  CCPP_PHYS_SUITE = \"${CCPP_PHYS_SUITE}\"
  FV3GFS_FILE_FMT_ICS = \"${FV3GFS_FILE_FMT_ICS}\""
      fi
#
# If CCPP is not being used, the only physics suite that can be used is
# GFS.
#
    else
      tracers="[\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\"]"
    fi

  elif [ "${FV3GFS_FILE_FMT_ICS}" = "grib2" ]; then

    external_model="GFS"

    fn_grib2="${EXTRN_MDL_FNS[0]}"
    input_type="grib2"

  fi

  internal_GSD=False
  numsoil_out="4"
  replace_vgtyp=True
  replace_sotyp=True
  replace_vgfrc=True
  tg3_from_soil=False
  convert_nst=True

  ;;


"HRRRX")

  external_model="HRRR"

  fn_grib2="${EXTRN_MDL_FNS[0]}"
  input_type="grib2"

  internal_GSD=False
  cdate_min_HRRRX="2019111500"
  if [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" -o \
       "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ] && \
     [ ${CDATE} -gt ${cdate_min_HRRRX} ]; then
    print_info_msg "
Setting the chgres_cube namelist setting \"internal_GSD\" to \".true.\" in
order to read in land surface model (LSM) variables available in the
HRRRX grib2 files created after about \"${cdate_min_HRRRX}\"..."
    internal_GSD=True
  fi

  if [ "${USE_CCPP}" = "TRUE" ]; then
    if [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp_regional" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR_v1" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v0" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v1beta" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_CPT_v0" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v15p2" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v16beta" ]; then
      numsoil_out="4"
    elif [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ]; then
      numsoil_out="9"
    else
      print_err_msg_exit "\
The parameter \"numsoil_out\" has not been defined for this combination 
of external model (EXTRN_MDL_NAME_ICS) and physics suite (CCPP_PHYS_SUITE):
  EXTRN_MDL_NAME_ICS = \"${EXTRN_MDL_NAME_ICS}\"
  CCPP_PHYS_SUITE = \"${CCPP_PHYS_SUITE}\""
    fi
  fi
#
# These geogrid files need to be moved to more permanent locations.
#
  if [ "${MACHINE}" = "HERA" ]; then
    geogrid_file_input_grid="/scratch2/BMC/det/beck/FV3-LAM/geo_em.d01.nc_HRRRX"
  elif [ "${MACHINE}" = "JET" ]; then
    geogrid_file_input_grid="/misc/whome/rtrr/HRRR/static/WPS/geo_em.d01.nc"
  fi

  replace_vgtyp=False
  replace_sotyp=False
  replace_vgfrc=False
  tg3_from_soil=True
  convert_nst=False

  ;;

"RAPX")

  external_model="RAP"

  fn_grib2="${EXTRN_MDL_FNS[0]}"
  input_type="grib2"

  internal_GSD=False

  if [ "${USE_CCPP}" = "TRUE" ]; then
    if [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp_regional" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_CPT_v0" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR_v1" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v0" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_RRFS_v1beta" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v15p2" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v16beta" ]; then
      numsoil_out="4"
    elif [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ]; then
      numsoil_out="9"
    else
      print_err_msg_exit "\
The parameter \"numsoil_out\" has not been defined for this combination 
of external model (EXTRN_MDL_NAME_ICS) and physics suite (CCPP_PHYS_SUITE):
  EXTRN_MDL_NAME_ICS = \"${EXTRN_MDL_NAME_ICS}\"
  CCPP_PHYS_SUITE = \"${CCPP_PHYS_SUITE}\""
    fi
  fi
#
# These geogrid files need to be moved to more permanent locations.
#
  if [ "${MACHINE}" = "HERA" ]; then
    geogrid_file_input_grid="/scratch2/BMC/det/beck/FV3-LAM/geo_em.d01.nc_RAPX"
  elif [ "${MACHINE}" = "JET" ]; then
    geogrid_file_input_grid="/misc/whome/rtrr/HRRR/static/WPS/geo_em.d01.nc"
  fi

  replace_vgtyp=False
  replace_sotyp=False
  replace_vgfrc=False
  tg3_from_soil=True
  convert_nst=False

  ;;

*)
  print_err_msg_exit "\
External-model-dependent namelist variables have not yet been specified
for this external model:
  EXTRN_MDL_NAME_ICS = \"${EXTRN_MDL_NAME_ICS}\""
  ;;

esac
#
#-----------------------------------------------------------------------
#
# Get the starting month, day, and hour of the the external model forecast.
#
#-----------------------------------------------------------------------
#
mm="${EXTRN_MDL_CDATE:4:2}"
dd="${EXTRN_MDL_CDATE:6:2}"
hh="${EXTRN_MDL_CDATE:8:2}"
#
#-----------------------------------------------------------------------
#
# Check that the executable that generates the ICs exists.
#
#-----------------------------------------------------------------------
#
exec_fn="chgres_cube.exe"
exec_fp="$EXECDIR/${exec_fn}"
if [ ! -f "${exec_fp}" ]; then
  print_err_msg_exit "\
The executable (exec_fp) for generating initial conditions on the FV3-LAM
native grid does not exist:
  exec_fp = \"${exec_fp}\"
Please ensure that you've built this executable."
fi
#
#-----------------------------------------------------------------------
#
# Build the FORTRAN namelist file that chgres_cube will read in.
#
#-----------------------------------------------------------------------
#
# For GFS physics, the character arrays tracers_input(:) and tracers(:)
# must be specified in the namelist file.  tracers_input(:) contains the
# tracer name to look for in the external model file(s), while tracers(:)
# contains the names to use for the tracers in the output NetCDF files
# that chgres creates (that will be read in by FV3).  Since when FV3
# reads these NetCDF files it looks for atmospheric traces as specified
# in the file field_table, tracers(:) should be set to the names in
# field_table.
#
# NOTE: This process should be automated where the set of elements that
# tracers(:) should be set to is obtained from reading in field_table.
#
# To know how to set tracers_input(:), you have to know the names of the
# variables in the input atmospheric nemsio file (usually this file is
# named gfs.t00z.atmanl.nemsio).
#
# It is not quite clear how these should be specified.  Here are a list
# of examples:
#
# [Gerard.Ketefian@tfe05] /scratch3/.../chgres_cube.fd/run (feature/chgres_grib2_gsk)
# $ grep -n -i "tracers" * | grep theia
# config.C1152.l91.atm.theia.nml:24: tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C1152.l91.atm.theia.nml:25: tracers_input="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C48.gaussian.theia.nml:20: tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C48.gaussian.theia.nml:21: tracers_input="spfh","clwmr","o3mr","icmr","rwmr","snmr","grle"
# config.C48.gfs.gaussian.theia.nml:21: tracers="sphum","liq_wat","o3mr"
# config.C48.gfs.gaussian.theia.nml:22: tracers_input="spfh","clwmr","o3mr"
# config.C48.gfs.spectral.theia.nml:21: tracers_input="spfh","o3mr","clwmr"
# config.C48.gfs.spectral.theia.nml:22: tracers="sphum","o3mr","liq_wat"
# config.C48.theia.nml:21: tracers="sphum","liq_wat","o3mr"
# config.C48.theia.nml:22: tracers_input="spfh","clwmr","o3mr"
# config.C768.atm.theia.nml:24: tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C768.atm.theia.nml:25: tracers_input="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C768.l91.atm.theia.nml:24: tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C768.l91.atm.theia.nml:25: tracers_input="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C768.nest.atm.theia.nml:22: tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
# config.C768.nest.atm.theia.nml:23: tracers_input="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"


# fix_dir_target_grid="${BASEDIR}/ESG_grid_HRRR_like_fix_files_chgres_cube"
# base_install_dir="${SORCDIR}/chgres_cube.fd"

#
# Create a multiline variable that consists of a yaml-compliant string
# specifying the values that the namelist variables need to be set to
# (one namelist variable per line, plus a header and footer).  Below,
# this variable will be passed to a python script that will create the
# namelist file.
#
settings="
'config': {
 'fix_dir_target_grid': ${FIXLAM},
 'mosaic_file_target_grid': ${FIXLAM}/${CRES}${DOT_OR_USCORE}mosaic.halo${NH4}.nc,
 'orog_dir_target_grid': ${FIXLAM},
 'orog_files_target_grid': ${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${NH4}.nc,
 'vcoord_file_target_grid': ${FIXam}/global_hyblev.l65.txt,
 'mosaic_file_input_grid': '',
 'orog_dir_input_grid': '',
 'base_install_dir': ${CHGRES_DIR},
 'wgrib2_path': ${wgrib2_dir},
 'data_dir_input_grid': ${extrn_mdl_staging_dir},
 'atm_files_input_grid': ${fn_atm_nemsio},
 'sfc_files_input_grid': ${fn_sfc_nemsio},
 'grib2_file_input_grid': \"${fn_grib2}\",
 'cycle_mon': $((10#$mm)),
 'cycle_day': $((10#$dd)),
 'cycle_hour': $((10#$hh)),
 'convert_atm': True,
 'convert_sfc': True,
 'convert_nst': ${convert_nst},
 'regional': 1,
 'halo_bndy': ${NH4},
 'input_type': ${input_type},
 'external_model': ${external_model},
 'tracers_input': ${tracers_input},
 'tracers': ${tracers},
 'phys_suite': ${phys_suite},
 'internal_GSD': ${internal_GSD},
 'numsoil_out': ${numsoil_out},
 'geogrid_file_input_grid': ${geogrid_file_input_grid},
 'replace_vgtyp': ${replace_vgtyp},
 'replace_sotyp': ${replace_sotyp},
 'replace_vgfrc': ${replace_vgfrc},
 'tg3_from_soil': ${tg3_from_soil},
}
"
#
# Call the python script to create the namelist file.
#
nml_fn="fort.41"
${USHDIR}/set_namelist.py -q -u "$settings" -o ${nml_fn} || \
  print_err_msg_exit "\
Call to python script set_namelist.py to set the variables in the namelist
file read in by the ${exec_fn} executable failed.  Parameters passed to
this script are:
  Name of output namelist file:
    nml_fn = \"${nml_fn}\"
  Namelist settings specified on command line (these have highest precedence):
    settings =
$settings"
#
#-----------------------------------------------------------------------
#
# Run chgres_cube.
#
#-----------------------------------------------------------------------
#
# NOTE:
# Often when the chgres_cube.exe run fails, it still returns a zero re-
# turn code, so the failure isn't picked up the the logical OR (||) be-
# low.  That should be fixed.  This might be due to the APRUN command -
# maybe that is returning a zero exit code even though the exit code
# of chgres_cube is nonzero.
# A similar thing happens in the forecast task.
#
${APRUN} ${exec_fp} || \
  print_err_msg_exit "\
Call to executable (exec_fp) to generate surface and initial conditions
(ICs) files for the FV3-LAM failed:
  exec_fp = \"${exec_fp}\"
The external model from which the ICs files are to be generated is:
  EXTRN_MDL_NAME_ICS = \"${EXTRN_MDL_NAME_ICS}\"
The external model files that are inputs to the executable (exec_fp) are
located in the following directory:
  extrn_mdl_staging_dir = \"${extrn_mdl_staging_dir}\""
#
#-----------------------------------------------------------------------
#
# Move initial condition, surface, control, and 0-th hour lateral bound-
# ary files to ICs_BCs directory.
#
#-----------------------------------------------------------------------
#
mv_vrfy out.atm.tile${TILE_RGNL}.nc \
        ${ics_dir}/gfs_data.tile${TILE_RGNL}.halo${NH0}.nc

mv_vrfy out.sfc.tile${TILE_RGNL}.nc \
        ${ics_dir}/sfc_data.tile${TILE_RGNL}.halo${NH0}.nc

mv_vrfy gfs_ctrl.nc ${ics_dir}

mv_vrfy gfs_bndy.nc ${ics_dir}/gfs_bndy.tile${TILE_RGNL}.000.nc
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Initial condition, surface, and zeroth hour lateral boundary condition
files (in NetCDF format) for FV3 generated successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
