; #############################################################################
; carbon_cycle/mvi.ncl
; #############################################################################
; DIAGNOSTIC SCRIPT TO CREATE MVI-IAV-TREND PLOT
; Author: Alessandro Anav (University of Exeter, UK)
; EMBRACE project
; #############################################################################
;
; Description
;    Calculates the model variability index (MVI), interannual variability
;    (IAV) and mean, and draws them in a 3D scatter plot.
;
; Required recipe attributes:
;     grid: target grid for the regridding.
;     region: region to be averaged.
;     ref_dataset: reference for the MVI calculation.
;
; Optional recipe attributes:
;
; Caveats:
;     The derived variables pr-mmday and tas-degC needs to be used in order
;     to get the correct linear trend. For land variables nbp, gpp and lai, it
;     is recommended to use the masked version (NBP, GPP and LAI, respectively)
;     in order to have a consistent land mask for all datasets.
;
; Modification history
;   * 20180814-A_schl_ma: continued porting to v2.0
;   * 20180619-A_wenz_sa: adopted script to v2
;   * 20151130-A_laue_ax: moved call to write_references to beginning of code
;   * 20151104-A_righ_ma: graphic part moved to external plot_scripts.
;   * 20151102-A_righ_ma: replacing area functions with ESMValTool functions.
;   * 201507??-A_wenz_sa: adapted to ESMValTool structure.
;   * 201505??-A_anav_al: written.
;
; #############################################################################

load "./interface_scripts/interface.ncl"

load "./diag_scripts/shared/latlon.ncl"
load "./diag_scripts/shared/statistics.ncl"
load "./diag_scripts/shared/regridding.ncl"
load "./diag_scripts/shared/scaling.ncl"

load "./diag_scripts/shared/plot/scatterplot.ncl"
load "./diag_scripts/shared/plot/style.ncl"


begin

    enter_msg(diag_script, "")
    log_info("++++++++++++++++++++++++++++++++++++++++++")
    log_info(diag_script + " (var: " + variables(0) + ")")
    log_info("++++++++++++++++++++++++++++++++++++++++++")

    dim_MOD = dimsizes(dataset_info@dataset)
    dim_VAR = dimsizes(variables)
    var0 = variables(0)
    field_type0 = field_types(0)

    write_references(diag_script,                  \  ; script name
                     (/"A_anav_al"/),              \  ; authors
                     (/"A_wenz_sa", "A_righ_ma"/), \  ; contributors
                     (/"D_anav13jclim"/),          \  ; diag_references
                     (/""/),                       \  ; obs_references
                     (/"P_embrace"/))                 ; proj_references

    ;; Define file type
    file_type = config_user_info@output_file_type

    ;; Check required diag_script_info attributes
    req_atts = (/"grid", "region"/)
    exit_if_missing_atts(diag_script_info, req_atts)

    ;; Check field type
    plot_fields = (/"T2Ms"/)
    if (field_type0.ne.plot_fields) then
        error_msg("f", diag_script, "", "can't use field " + field_type + \
                  " for this diag_script")
    end if
    delete(plot_fields)

    ;; Set region
    region = select_region(diag_script_info@region)

    ;; Output plot directory, set path for saving plots
    output_dir = config_user_info@plot_dir
    if (.not.isfilepresent(config_user_info@plot_dir)) then
      system("mkdir -p " + config_user_info@plot_dir)
    end if

    ;; Set time range
    start_year = min(stringtoint(dataset_info@start_year))
    end_year = max(stringtoint(dataset_info@end_year))
    all_years = ispan(start_year, end_year, 1)

    ;; Regrid to destination grid
    grid_resolution        = diag_script_info@grid

    if (grid_resolution.eq."0.5deg")    then
        dNLON = 720
        dNLAT = 360
    else if (grid_resolution.eq."1deg") then
        dNLON = 360
        dNLAT = 180
    else if (grid_resolution.eq."2deg") then
        dNLON = 180
        dNLAT = 90
    else
        error_msg("f", diag_script, "", "Wrong destination grid defined: " + \
                  diag_script_info@grid)
    end if
    end if
    end if

    ;; Gridded matrix for a given resolution where all yearly data are stored
    all_data_yearly = \
        new((/dim_MOD, end_year - start_year + 1, dNLAT, dNLON/), float)
    all_data_yearly!0 = "dataset"
    all_data_yearly!1 = "year"
    all_data_yearly!2 = "lat"
    all_data_yearly!3 = "lon"

    ;; Gridded matrix for a given resolution where all MVI data are stored
    MVI_all_data = new((/dim_MOD, dNLAT, dNLON/), float)
    MVI_all_data!0 = "dataset"
    MVI_all_data!1 = "lat"
    MVI_all_data!2 = "lon"

    ;; Gridded matrix for a given resolution where all trend data are stored
    Trend_all_data = new((/dim_MOD, dNLAT, dNLON/), float)
    Trend_all_data!0 = "dataset"
    Trend_all_data!1 = "lat"
    Trend_all_data!2 = "lon"

    ;; Loop over datasets and regrid
    do imod = 0, dim_MOD - 1

        log_info("Processing " + dataset_info@dataset(imod))

        ;; Extract dataset corresponding data
        var  = read_data(imod, var0, field_type0)

        ;; Computing annual mean
        data_annual = time_operations(var, toint(dataset_info@start_year(imod)), \
                                      toint(dataset_info@end_year(imod)), "average",\
                                      "yearly", True)

        ;; Place array in dataset specific time range
        idx1 = start_year - toint(dataset_info@start_year(imod))
        idx2 = dimsizes(all_years) - \
            (end_year - toint(dataset_info@end_year(imod))) - 1

            all_data_yearly(imod, idx1:idx2, :, :) = data_annual
            all_data_yearly&dataset = dataset_info@dataset
            copy_VarAtts(data_annual,all_data_yearly)

        ;; Cleaning up
        delete(var)
        delete(data_annual)

    end do  ; end loop over datasets

    ;; Compute annual mean, MVI, trend
    MVI_all_data&dataset = dataset_info@dataset
    MVI_all_data&lat = all_data_yearly&lat
    MVI_all_data&lon = all_data_yearly&lon
    MVI_all_data@_FillValue = 1.e20

    Trend_all_data&dataset = dataset_info@dataset
    Trend_all_data&lat = all_data_yearly&lat
    Trend_all_data&lon = all_data_yearly&lon
    Trend_all_data@_FillValue = 1.e20

    ;; Determine reference dataset and compute MVI
    ref_ind = get_ref_dataset_idx(dataset_info, variable_info@reference_dataset);ind(dataset_info@dataset.eq.variable_info@reference_dataset)
    if (ismissing(ref_ind)) then
        error_msg("f", diag_script, "", "no adequate reference dataset provided")
    end if

    log_info("Reference dataset: " + dataset_info@dataset(ref_ind))
    reference = all_data_yearly(ref_ind, :, :, :)
    ref = dim_stddev_n(reference, 0)
    ref = where(ref.ne.0, ref, all_data_yearly@_FillValue)

    ;; Loop over datasets
    do imod = 0, dim_MOD - 1

        temp  = all_data_yearly(imod, :, :, :)
        dataset = dim_stddev_n(temp, 0)

        ;; Prevents a division by 0
        dataset = where(dataset.ne.0, dataset, all_data_yearly@_FillValue)

        ;; Commpute MVI
        MVI_all_data(imod, :, :) = (dataset/ref - ref/dataset) ^ 2
        delete(dataset)
        delete(temp)

        dataset = all_data_yearly(imod, :, :, :)

         ;; Commpute Trend
        rc = regCoef_n(1.0 * all_years, dataset, 0, 0)
        rc!0 = "lat"
        rc!1 = "lon"
        rc&lat = dataset&lat
        rc&lon = dataset&lon
        Trend_all_data(imod, :, :) = rc
        delete(dataset)
        delete(rc)

    end do
    copy_VarAtts(all_data_yearly,Trend_all_data)

    ;; Put a cap. Where MVI > 1000 we assing a FillValue
    MVI_all_data = where(MVI_all_data.lt.10, MVI_all_data, 50)

    ;; Special case for LAI
    ;; Since datasets have different land covers, all sparse vegetated points
    ;; must be masked out
    if (var0.eq."LAI") then
        all_data_yearly = where(all_data_yearly.ge.0.025, \
                                all_data_yearly, 1.e20)
    end if

    all_annual_mean = dim_avg_n_Wrap(all_data_yearly, 1)
;    all_annual_mean!0 = "dataset"               ;;DELETE part if script works in v2!!!
;    all_annual_mean!1 = "lat"
;    all_annual_mean!2 = "lon"

;    all_annual_mean&dataset = dataset_info@dataset
;    all_annual_mean&lat = all_data_yearly&lat
;    all_annual_mean&lon = all_data_yearly&lon
;    all_annual_mean@units = all_data_yearly@units
    delete(all_data_yearly)

    Mean_var = new((/dim_MOD/), typeof(all_annual_mean))
    Mean_var!0 = "dataset"
    Mean_var&dataset = dataset_info@dataset

    Trend_var = new((/dim_MOD/), typeof(all_annual_mean))
    Trend_var!0 = "dataset"
    Trend_var&dataset = dataset_info@dataset

    MVI_var = new((/dim_MOD/), typeof(all_annual_mean))
    MVI_var!0 = "dataset"
    MVI_var&dataset = dataset_info@dataset

    ;; Compute global area
    area = map_area(all_annual_mean&lat, all_annual_mean&lon)

    ;; Set type of area operation (flux vs. non-flux variables)
    if (all_annual_mean@units.eq."kg m-2 s-1") then
        sp_opt = "sum"  ; for flux variable
    else
        sp_opt = "average"  ; for non-flux variable
    end if

    ;; Loop over datasets
    do imod = 0, dim_MOD - 1
        Mean_var(imod) = area_operations(all_annual_mean(imod, :, :), \
                                         region(0), region(1), region(2), \
                                         region(3), sp_opt, True)
        Trend_var(imod) = area_operations(Trend_all_data(imod, :, :), \
                                          region(0), region(1), region(2), \
                                          region(3), sp_opt, True)
        MVI_var(imod) = area_operations(MVI_all_data(imod, :, :), \
                                        region(0), region(1), region(2), \
                                        region(3), "average", True)
    end do

    ;; Diagnostic-specific units conversions
    MVI_var@units = "1"

    if (isatt(variable_info, "plot_units")) then
        Mean_var  = convert_units(Mean_var, variable_info@plot_units)
        Trend_tmp = convert_units(Trend_var, variable_info@plot_units)

        if (dataset_info@mip(0).eq."Lmon") then
          Trend_var = Trend_tmp
          Trend_var@units = Trend_tmp@units + " y-1"
        else
          Trend_var = Trend_tmp * 10.
          Trend_var@units = Trend_tmp@units + " decade-1"
        end if
        delete(Trend_tmp)
    end if

    ;; Optional output to NetCDF
    if (config_user_info@write_netcdf.eq."True") then

      ;; Set path for saving processed data
      if (.not.isfilepresent(config_user_info@work_dir)) then
        system("mkdir -p " + config_user_info@work_dir)
      end if

        ;; Mean
        new_path = config_user_info@work_dir + \
                   basename(diag_script) + "_mean_" + var0 + ".nc"

        Mean_var@var = var0
        Mean_var@diag_script = diag_script
        Mean_var@ncdf = new_path
        ncdf_outfile = ncdf_write(Mean_var, new_path)

        ;; Trend
        new_path = config_user_info@work_dir + \
                   basename(diag_script) + "_trend_" + var0 + ".nc"
        Trend_var@var = var0
        Trend_var@diag_script = diag_script
        Trend_var@ncdf = new_path
        ncdf_outfile = ncdf_write(Trend_var, new_path)

        ;; MVI
        new_path = config_user_info@work_dir + \
                   basename(diag_script) + "_MVI_" + var0 + ".nc"
        MVI_var@var = var0
        MVI_var@diag_script = diag_script
        MVI_var@ncdf = new_path
        ncdf_outfile = ncdf_write(MVI_var, new_path)

    end if

    ;; Set plot output file
    outfile = output_dir + diag_script + "_" + var0 + "_" + \
        region@name
    wks = gsn_open_wks(file_type, outfile)
    gsn_define_colormap(wks, "BlAqGrYeOrReVi200")
    gsn_reverse_colormap(wks)

    ;; Pack data
    data_arr = new((/3, dimsizes(Mean_var)/), float)
    data_arr(0, :) = (/Mean_var/)
    data_arr(1, :) = (/Trend_var/)
    data_arr(2, :) = (/MVI_var/)
    data_arr!0 = "statistic"
    data_arr!1 = "datasets"
    data_arr&statistic = (/"mean", "linear trend", "MVI"/)
    data_arr&datasets = dataset_info@dataset
    data_arr@units = (/Mean_var@units, Trend_var@units, "1"/)

    ;; Set levels for the color coding
    tmp = MVI_var
    tmp(ref_ind) = tmp@_FillValue
    nlevs = 11
    tmp := nice_mnmxintvl(min(tmp), max(tmp), nlevs, True)
    levs = decimalPlaces(fspan(tmp(0), tmp(1), 11), 2, True)
    delete(tmp)

    ;; Draw a 3D scatterplot
    data_arr@res_tiMainString = var0 + " - " + diag_script_info@region
    plot = scatterplot3D(wks, data_arr, var0, levs)
    draw(plot)
    frame(wks)

    ;; Attach Metadata to plot
    ;alltags = array_append_record(tags, region@DM_tag, 0)
    ;alltags := array_append_record(alltags,\
    ;       (/"PT_scatter", "PT_zonal", "ST_mean", "ST_trend", \
    ;         "ST_clim", "ST_var"/), 0)
    ;caption =  "Scatterplot for multiyear average " + variables(0) + \
    ;           " in x axis, its linear trend in y axis, and MVI." + \
   ;            " Like Anav et al. Fig 1 bottom"
   ; id = diag_script
   ; climofiles = new(dimsizes(dataset_info@dataset) * dimsizes(variables), string)
    ;do n_var = 0, dimsizes(variables) - 1
    ;    do imod = 0, dimsizes(dataset_info@dataset) - 1
    ;        climofiles(n_var * dimsizes(dataset_info@dataset) + imod) = \
     ;                   interface_get_inpaths(imod) + "/" + \
     ;                   interface_get_infile(variables(n_var), field_types(n_var), imod)
     ;   end do
    ;end do
    ;contrib_authors = (/"A_anav_al", "A_wenz_sa", "A_righ_ma"/)

    ;;NOTE: not implemented in v2 yet
    ;ESMValMD(outfile+"."+file_type, alltags, caption, id, variables, dataset_info@dataset, climofiles, diag_script, contrib_authors)

    ;delete([/alltags, caption, id, climofiles/])
    delete(data_arr)

    leave_msg(diag_script, "")

end