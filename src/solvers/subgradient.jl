"""
    SubGradientMethodState <: AbstractManoptSolverState

stores option values for a [`subgradient_method`](@ref) solver

# Fields

* $(_field_p)
* `p_star`: optimal value
* $(_field_retr)
* $(_field_step)
* $(_field_stop)
* `X`: the current element from the possible subgradients at `p` that was last evaluated.

# Constructor

    SubGradientMethodState(M::AbstractManifold, p; kwargs...)

Initialise the Subgradient method state to initial point `p`

# Keyword arguments

* $(_kw_retraction_method_default): $(_kw_retraction_method)
* `stepsize=`[`default_stepsize`](@ref)`(M, SubGradientMethodState)`,
  which here defaults to [`ConstantStepsize`](@ref)`(M)`
* `stopping_criterion=[`StopAfterIteration`](@ref)`(5000)`: $(_kw_stopping_criterion)
* $(_kw_X_default): $(_kw_X)
"""
mutable struct SubGradientMethodState{
    TR<:AbstractRetractionMethod,TS<:Stepsize,TSC<:StoppingCriterion,P,T
} <: AbstractManoptSolverState where {P,T}
    p::P
    p_star::P
    retraction_method::TR
    stepsize::TS
    stop::TSC
    X::T
    function SubGradientMethodState(
        M::TM,
        p::P;
        stopping_criterion::SC=StopAfterIteration(5000),
        stepsize::S=default_stepsize(M, SubGradientMethodState),
        X::T=zero_vector(M, p),
        retraction_method::TR=default_retraction_method(M, typeof(p)),
    ) where {
        TM<:AbstractManifold,
        P,
        T,
        SC<:StoppingCriterion,
        S<:Stepsize,
        TR<:AbstractRetractionMethod,
    }
        return new{TR,S,SC,P,T}(
            p, copy(M, p), retraction_method, stepsize, stopping_criterion, X
        )
    end
end
function show(io::IO, sgms::SubGradientMethodState)
    i = get_count(sgms, :Iterations)
    Iter = (i > 0) ? "After $i iterations\n" : ""
    Conv = indicates_convergence(sgms.stop) ? "Yes" : "No"
    s = """
    # Solver state for `Manopt.jl`s Subgradient Method
    $Iter
    ## Parameters
    * retraction method: $(sgms.retraction_method)

    ## Stepsize
    $(sgms.stepsize)

    ## Stopping criterion

    $(status_summary(sgms.stop))
    This indicates convergence: $Conv"""
    return print(io, s)
end
get_iterate(sgs::SubGradientMethodState) = sgs.p
get_subgradient(sgs::SubGradientMethodState) = sgs.X
function set_iterate!(sgs::SubGradientMethodState, M, p)
    copyto!(M, sgs.p, p)
    return sgs
end
function default_stepsize(M::AbstractManifold, ::Type{SubGradientMethodState})
    return ConstantStepsize(M)
end

_doc_SGM = """
    subgradient_method(M, f, ∂f, p=rand(M); kwargs...)
    subgradient_method(M, sgo, p=rand(M); kwargs...)
    subgradient_method!(M, f, ∂f, p; kwargs...)
    subgradient_method!(M, sgo, p; kwargs...)

perform a subgradient method ``p^{(k+1)} = $(_l_retr)\\bigl(p^{(k)}, s^{(k)}∂f(p^{(k)})\\bigr)``,
where ``$(_l_retr)`` is a retraction, ``s^{(k)}`` is a step size.

Though the subgradient might be set valued,
the argument `∂f` should always return _one_ element from the subgradient, but
not necessarily deterministic.
For more details see [FerreiraOliveira:1998](@cite).

# Input

$(_arg_M)
$(_arg_f)
* `∂f`: the (sub)gradient ``∂ f: $(_l_M) → T$(_l_M)`` of f
$(_arg_p)

alternatively to `f` and `∂f` a [`ManifoldSubgradientObjective`](@ref) `sgo` can be provided.

# Optional

* $(_kw_evaluation_default): $(_kw_evaluation)
* $(_kw_retraction_method_default): $(_kw_retraction_method)
* `stepsize=`[`default_stepsize`](@ref)`(M, SubGradientMethodState)`: $(_kw_stepsize)
  which here defaults to [`ConstantStepsize`](@ref)`(M)`
* `stopping_criterion=[`StopAfterIteration`](@ref)`(5000)`: $(_kw_stopping_criterion)
* $(_kw_X_default): $(_kw_X)

and the ones that are passed to [`decorate_state!`](@ref) for decorators.

# Output

the obtained (approximate) minimizer ``p^*``, see [`get_solver_return`](@ref) for details
"""

@doc "$(_doc_SGM)"
subgradient_method(::AbstractManifold, args...; kwargs...)
function subgradient_method(M::AbstractManifold, f, ∂f; kwargs...)
    return subgradient_method(M, f, ∂f, rand(M); kwargs...)
end
function subgradient_method(
    M::AbstractManifold,
    f,
    ∂f,
    p;
    evaluation::AbstractEvaluationType=AllocatingEvaluation(),
    kwargs...,
)
    sgo = ManifoldSubgradientObjective(f, ∂f; evaluation=evaluation)
    return subgradient_method(M, sgo, p; evaluation=evaluation, kwargs...)
end
function subgradient_method(
    M::AbstractManifold,
    f,
    ∂f,
    p::Number;
    evaluation::AbstractEvaluationType=AllocatingEvaluation(),
    kwargs...,
)
    q = [p]
    f_(M, p) = f(M, p[])
    ∂f_ = _to_mutating_gradient(∂f, evaluation)
    rs = subgradient_method(M, f_, ∂f_, q; evaluation=evaluation, kwargs...)
    #return just a number if  the return type is the same as the type of q
    return (typeof(q) == typeof(rs)) ? rs[] : rs
end
function subgradient_method(
    M::AbstractManifold, sgo::O, p; kwargs...
) where {O<:Union{ManifoldSubgradientObjective,AbstractDecoratedManifoldObjective}}
    q = copy(M, p)
    return subgradient_method!(M, sgo, q; kwargs...)
end

@doc "$(_doc_SGM)"
subgradient_method!(M::AbstractManifold, args...; kwargs...)
function subgradient_method!(
    M::AbstractManifold,
    f,
    ∂f,
    p;
    evaluation::AbstractEvaluationType=AllocatingEvaluation(),
    kwargs...,
)
    sgo = ManifoldSubgradientObjective(f, ∂f; evaluation=evaluation)
    return subgradient_method!(M, sgo, p; evaluation=evaluation, kwargs...)
end
function subgradient_method!(
    M::AbstractManifold,
    sgo::O,
    p;
    retraction_method::AbstractRetractionMethod=default_retraction_method(M, typeof(p)),
    stepsize::Stepsize=default_stepsize(M, SubGradientMethodState),
    stopping_criterion::StoppingCriterion=StopAfterIteration(5000),
    X=zero_vector(M, p),
    kwargs...,
) where {O<:Union{ManifoldSubgradientObjective,AbstractDecoratedManifoldObjective}}
    dsgo = decorate_objective!(M, sgo; kwargs...)
    mp = DefaultManoptProblem(M, dsgo)
    sgs = SubGradientMethodState(
        M,
        p;
        stopping_criterion=stopping_criterion,
        stepsize=stepsize,
        retraction_method=retraction_method,
        X=X,
    )
    dsgs = decorate_state!(sgs; kwargs...)
    solve!(mp, dsgs)
    return get_solver_return(get_objective(mp), dsgs)
end
function initialize_solver!(mp::AbstractManoptProblem, sgs::SubGradientMethodState)
    M = get_manifold(mp)
    copyto!(M, sgs.p_star, sgs.p)
    sgs.X = zero_vector(M, sgs.p)
    return sgs
end
function step_solver!(mp::AbstractManoptProblem, sgs::SubGradientMethodState, k)
    get_subgradient!(mp, sgs.X, sgs.p)
    step = get_stepsize(mp, sgs, k)
    M = get_manifold(mp)
    retract!(M, sgs.p, sgs.p, -step * sgs.X, sgs.retraction_method)
    (get_cost(mp, sgs.p) < get_cost(mp, sgs.p_star)) && copyto!(M, sgs.p_star, sgs.p)
    return sgs
end
get_solver_result(sgs::SubGradientMethodState) = sgs.p_star
function (cs::ConstantStepsize)(
    amp::AbstractManoptProblem, sgs::SubGradientMethodState, ::Any, args...; kwargs...
)
    s = cs.length
    if cs.type == :absolute
        ns = norm(get_manifold(amp), get_iterate(sgs), get_subgradient(sgs))
        if ns > eps(eltype(s))
            s /= ns
        end
    end
    return s
end
function (s::DecreasingStepsize)(
    amp::AbstractManoptProblem, sgs::SubGradientMethodState, k::Int, args...; kwargs...
)
    ds = (s.length - k * s.subtrahend) * (s.factor^k) / ((k + s.shift)^(s.exponent))
    if s.type == :absolute
        ns = norm(get_manifold(amp), get_iterate(sgs), get_subgradient(sgs))
        if ns > eps(eltype(ds))
            ds /= ns
        end
    end
    return ds
end
