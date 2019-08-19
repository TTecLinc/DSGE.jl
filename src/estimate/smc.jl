"""
```
smc(m::AbstractDSGEModel, data::Matrix; verbose::Symbol, old_data::Matrix)
smc(m::AbstractDSGEModel, data::DataFrame)
smc(m::AbstractDSGEModel)
```

### Arguments:

- `m`: A model object, which stores parameter values, prior dists, bounds, and various
    other settings that will be referenced
- `data`: A matrix or dataframe containing the time series of the observables used in
    the calculation of the posterior/likelihood
- `old_data`: A matrix containing the time series of observables of previous data
    (with `data` being the new data) for the purposes of a time tempered estimation
    (that is, using the posterior draws from a previous estimation as the initial set
    of draws for an estimation with new data)

### Keyword Arguments:
- `verbose`: Desired frequency of function progress messages printed to standard out.
	- `:none`: No status updates will be reported.
	- `:low`: Status updates for SMC initialization and recursion will be included.
	- `:high`: Status updates for every iteration of SMC is output, which includes
    the mean and standard deviation of each parameter draw after each iteration,
    as well as calculated acceptance rate, ESS, and number of times resampled.

### Outputs

- `cloud`: The ParticleCloud object containing all of the information about the
    parameter values from the sample, their respective log-likelihoods, the ESS
    schedule, tempering schedule etc., which is saved in the saveroot.

### Overview

Sequential Monte Carlo can be used in lieu of Random Walk Metropolis Hastings to
    generate parameter samples from high-dimensional parameter spaces using
    sequentially constructed proposal densities to be used in iterative importance
    sampling.

The implementation here is based on Edward Herbst and Frank Schorfheide's 2014 paper
    'Sequential Monte Carlo Sampling for DSGE Models' and the code accompanying their
    book 'Bayesian Estimation of DSGE Models'.

SMC is broken up into three main steps:

- `Correction`: Reweight the particles from stage n-1 by defining incremental weights,
    which gradually "temper in" the likelihood function p(Y|θ)^(ϕ_n - ϕ_n-1) into the
    normalized particle weights.
- `Selection`: Resample the particles if the distribution of particles begins to
    degenerate, according to a tolerance level for the ESS.
- `Mutation`: Propagate particles {θ(i), W(n)} via N(MH) steps of a Metropolis
    Hastings algorithm.
"""
function smc(m::AbstractDSGEModel, data::Matrix{Float64};
             verbose::Symbol = :low,
             old_data::Matrix{Float64} = Matrix{Float64}(undef, size(data, 1), 0),
             old_cloud::ParticleCloud  = ParticleCloud(m, 0),
             recompute_transition_equation::Bool = true, run_test::Bool = false,
             filestring_addl::Vector{String} = Vector{String}(),
             continue_intermediate::Bool = false, intermediate_stage_start::Int = 0,
             save_intermediate::Bool = false, intermediate_stage_increment::Int = 10)

    data_vintage = data_vintage(m)
    parallel = get_setting(m, :use_parallel_workers)
    n_blocks = get_setting(m, :n_smc_blocks)
    n_steps  = get_setting(m, :n_mh_steps_smc)
    previous_data_vintage = get_setting(m, :previous_data_vintage) ##

    λ      = get_setting(m, :λ)
    n_Φ    = get_setting(m, :n_Φ)
    tempering_target   = get_setting(m, :adaptive_tempering_target_smc)
    use_fixed_schedule = tempering_target == 0.0

    # Step 2 (Correction) settings
    resampling_method = get_setting(m, :resampler_smc)
    threshold_ratio   = get_setting(m, :resampling_threshold)
    threshold         = threshold_ratio * n_parts

    # Step 3 (Mutation) settings
    c      = get_setting(m, :step_size_smc)
    α      = get_setting(m, :mixture_proportion)
    target = accept = get_setting(m, :target_accept)


    recompute_transition_equation # TODO
    use_chand_recursion = get_setting(m, :use_chand_recursion)

    SMC.smc(my_likelihood, m.parameters, data; verbose = verbose, old_data = old_data,
            old_cloud = old_cloud, run_test = run_test, filestring_addl = filestring_addl,
            continue_intermediate = continue_intermediate,
            intermediate_stage_start = intermediate_stage_start,
            save_intermediate = save_intermediate,
            intermediate_stage_increment = intermediate_stage_increment,
            data_vintage = data_vintage, parallel = parallel)
end

function smc(m::AbstractDSGEModel, data::DataFrame; verbose::Symbol = :low,
             save_intermediate::Bool = false, intermediate_stage_increment::Int = 10,
             filestring_addl::Vector{String} = Vector{String}(undef, 0))
    data_mat = df_to_matrix(m, data)
    return smc(m, data_mat, verbose = verbose, save_intermediate = save_intermediate,
               filestring_addl = filestring_addl)
end

function smc(m::AbstractDSGEModel; verbose::Symbol = :low,
             save_intermediate::Bool = false, intermediate_stage_increment::Int = 10,
             filestring_addl::Vector{String} = Vector{String}(undef, 0))
    data = load_data(m)
    data_mat = df_to_matrix(m, data)
    return smc(m, data_mat, verbose=verbose, save_intermediate = save_intermediate,
               filestring_addl = filestring_addl)
end
