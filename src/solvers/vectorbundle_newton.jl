raw"""
    VectorbundleNewtonState{P,T} <: AbstractManoptSolverState

Is state for the vectorbundle Newton method

# Fields

* 'p': current iterate
* 'X': current Newton Direction
* `stopping_criterion`: stopping criterion
* `stepsize`: damping factor for the Newton direction
* `retraction_method`:  the retraction to use in the Newton update
* 'vector_transport_method': the vector transport to use

# Constructor

    VectorbundleNewtonState(M, E, F, connection_map, p=rand(M); kwargs...)

# Input

* 'M': domain manifold
* 'E': range vector bundle
* 'F': bundle map ``F:\mathcal M \to \mathcal E`` from Newton's method
* 'p': initial point

# Keyword arguments

* `X=`zero_vector(M, p)
* `retraction_method=``default_retraction_method`(M, typeof(p)),
* `stopping_criterion=`[`StopAfterIteration`](@ref)`(1000)``,
* `stepsize=`1.0
* `vector_transport_method=``default_vector_transport_method`(E, typeof(F(p)))

"""
#sub_problem und sub_state dokumentieren?
mutable struct VectorbundleNewtonState{
    P,
    #P2,
    T,
    Pr,
    St,
    TStop<:StoppingCriterion,
    TStep<:Stepsize,
    TRTM<:AbstractRetractionMethod,
    TVM<:AbstractVectorTransportMethod,
} <: AbstractGradientSolverState
    p::P
    p_trial::P
    X::T
    sub_problem::Pr
    sub_state::St
    stop::TStop
    stepsize::TStep
    retraction_method::TRTM
    vector_transport_method::TVM
    is_same::Bool
end

function VectorbundleNewtonState(
    M::AbstractManifold,
    E::AbstractManifold,
    F, #bundle_map
    p::P,
   # p_trial::P2,
   # same_point::Bool,
    sub_problem::Pr,
    sub_state::Op;
    X::T=zero_vector(M, p),
    retraction_method::RM=default_retraction_method(M, typeof(p)),
    stopping_criterion::SC=StopAfterIteration(1000),
    stepsize::S=default_stepsize(M, VectorbundleNewtonState),
    vector_transport_method::VTM=default_vector_transport_method(E, typeof(F(M, p))),
) where {
    P,
   # P2,
    T,
    Pr,
    Op,
    RM<:AbstractRetractionMethod,
    SC<:StoppingCriterion,
    S<:Stepsize,
    VTM<:AbstractVectorTransportMethod,
}
    return VectorbundleNewtonState{P,T,Pr,Op,SC,S,RM,VTM}(
        p,
        copy(M, p),
        X,
        sub_problem,
        sub_state,
        stopping_criterion,
        stepsize,
        retraction_method,
        vector_transport_method,
        true
    )
end

mutable struct AffineCovariantStepsize{T} <: Stepsize
    alpha::T
    #type::Symbol
    theta::Float64
    theta_des::Float64
    theta_acc::Float64
    #newton_direction::Vector{Float64}
end
function AffineCovariantStepsize(
    M::AbstractManifold=DefaultManifold(2);
    stepsize=1.0,
    theta=1.0,
    #type=:relative,
    theta_des=0.5,
    theta_acc=1.1*theta_des
)
    return AffineCovariantStepsize{typeof(stepsize)}(1.0, 1.3, theta_des, theta_acc)
end
function AffineCovariantStepsize(stepsize::T) where {T<:Number}
    return AffineCovariantStepsize{T}(1.0, 1.3, theta_des, theta_acc)
end
function (acs::AffineCovariantStepsize)(
    amp::AbstractManoptProblem, ams::VectorbundleNewtonState, ::Any, args...; kwargs...
)
    acs.alpha = 1.0
    acs.theta = 1.3
    alpha_new = 1.0
    #acs.theta_des = 0.5
    while acs.theta > acs.theta_acc
        acs.alpha = copy(alpha_new)
        X_alpha = acs.alpha * ams.X
        #println("differenz vorher=", norm(ams.p_trial - ams.p))
        retract!(get_manifold(amp), ams.p_trial, ams.p, X_alpha, ams.retraction_method)
        #println("differenz nachher=", norm(ams.p_trial - ams.p))
        ams.is_same = false
        #set_manopt_parameter!(ams.sub_problem, :Manifold, :Basepoint, ams.p)

        #set_iterate!(ams.sub_state, get_manifold(amp), zero_vector(get_manifold(amp), ams.p))
        #solve!(ams.sub_problem, ams.sub_state)

        simplified_newton = ams.sub_problem(amp, ams, 1)
        acs.theta = norm(simplified_newton)/norm(ams.X)
        #println("theta!!!=", acs.theta)
        alpha_new = min(1.0, ((acs.alpha*acs.theta_des)/(acs.theta)))
        #println("alpha!!!=", acs.alpha)
        #if acs.alpha < 1e-15
        #    println("Newton's method failed")
        #    return
        #end
    end
    #println("Hallo")
    println("alpha_end = ", acs.alpha)
    #acs.alpha = 1.0
    ams.is_same=true
    return acs.alpha
end
get_initial_stepsize(s::AffineCovariantStepsize) = 1.0

function default_stepsize(M::AbstractManifold, ::Type{VectorbundleNewtonState})
    return AffineCovariantStepsize(M)
end

function show(io::IO, vbns::VectorbundleNewtonState)
    i = get_count(vbns, :Iterations)
    Iter = (i > 0) ? "After $i iterations\n" : ""
    Conv = indicates_convergence(vbns.stop) ? "Yes" : "No"
    s = """
    # Solver state for `Manopt.jl`s Vectorbundle Newton Method
    $Iter
    ## Parameters
    * retraction method: $(vbns.retraction_method)
    * vector transport: $(vbns.vector_transport_method)
    * step size: $(vbns.stepsize)

    ## Stopping criterion

    $(status_summary(vbns.stop))
    This indicates convergence: $Conv"""
    return print(io, s)
end

@doc raw"""
    VectorbundleObjective{T<:AbstractEvaluationType} <: AbstractManifoldObjective{T}

specify an objective containing a vector bundle map, its derivative, and a connection map

# Fields

* `bundle_map!!`:       a mapping ``F: \mathcal M → \mathcal E`` into a vector bundle
* `derivative!!`: the derivative ``F': T\mathcal M → T\mathcal E`` of the bundle map ``F``.
* 'connection_map!!': connection map used in the Newton equation

# Constructors
    VectorbundleObjective(bundle_map, derivative, connection_map; evaluation=AllocatingEvaluation())

"""
mutable struct VectorbundleObjective{T<:AbstractEvaluationType,C,G,F} <:
       AbstractManifoldGradientObjective{T,C,G}
    bundle_map!!::C
    derivative!!::G
    connection_map!!::F
    scaling::Number
end
# TODO: Eventuell zweiter Parameter (a) Tensor/Matrix darstellung vs (b) action Darstellung
# oder über einen letzten parameter (a) ohne (b) mit

function VectorbundleObjective(
    bundle_map::C, derivative::G, connection_map::F; evaluation::E=AllocatingEvaluation()
) where {C,G,F,E<:AbstractEvaluationType, T}
    return VectorbundleObjective{E,C,G,F}(bundle_map, derivative, connection_map, 1.0)
end

raw"""
    VectorbundleManoptProblem{
    TM<:AbstractManifold,TV<:AbstractManifold,O<:AbstractManifoldObjective
}

Model a vector bundle problem, that consists of the domain manifold ``\mathcal M`` that is a AbstractManifold, the range vector bundle ``\mathcal E`` and an VectorbundleObjective
"""
# sollte da O nicht ein VectorbundleObjective sein?
struct VectorbundleManoptProblem{
    TM<:AbstractManifold,TV<:AbstractManifold,O<:AbstractManifoldObjective
} <: AbstractManoptProblem{TM}
    manifold::TM
    vectorbundle::TV
    objective::O
end

raw"""
    get_vectorbundle(vbp::VectorbundleManoptProblem)

    returns the range vector bundle stored within a [`VectorbundleManoptProblem`](@ref)
"""
get_vectorbundle(vbp::VectorbundleManoptProblem) = vbp.vectorbundle

raw"""
    get_manifold(vbp::VectorbundleManoptProblem)

    returns the domain manifold stored within a [`VectorbundleManoptProblem`](@ref)
"""
get_manifold(vbp::VectorbundleManoptProblem) = vbp.manifold

raw"""
    get_objective(mp::VectorbundleManoptProblem, recursive=false)

return the objective [`VectorbundleObjective`](@ref) stored within an [`VectorbundleManoptProblem`](@ref).
If `recursive` is set to true, it additionally unwraps all decorators of the `objective`
"""

function get_objective(vbp::VectorbundleManoptProblem, recursive=false)
    return recursive ? get_objective(vbp.objective, true) : vbp.objective
end

raw"""
    get_bundle_map(M, E, vbo::VectorbundleObjective, p)
    get_bundle_map!(M, E, X, vbo::VectorbundleObjective, p)
    get_bundle_map(P::VectorBundleManoptProblem, p)
    get_bundle_map!(P::VectorBundleManoptProblem, X, p)

    Evaluate the vector field ``F: \mathcal M → \mathcal E`` at ``p``
"""
function get_bundle_map(M, E, vbo::VectorbundleObjective, p)
    return vbo.bundle_map!!(M, p)
end
function get_bundle_map(M, E, vbo::VectorbundleObjective{InplaceEvaluation}, p)
    X = zero_vector(E, p)
    return vbo.bundle_map!!(M, X, p)
end
function get_bundle_map(vpb::VectorbundleManoptProblem, p)
    return get_bundle_map(
        get_manifold(vpb), get_vectorbundle(vpb), get_objective(vpb, true), p
    )
end
function get_bundle_map!(M, E, X, vbo::VectorbundleObjective{AllocatingEvaluation}, p)
    copyto!(E, p, X, vbo.bundle_map!!(M, p))
    return X
end
function get_bundle_map!(M, E, X, vbo::VectorbundleObjective{InplaceEvaluation}, p)
    vbo.bundle_map!!(M, X, p)
    return X
end
function get_bundle_map!(vbp::VectorbundleManoptProblem, X, p)
    get_bundle_map!(
        get_manifold(vbp), get_vectorbundle(vbp), X, get_objective(vbp, true), p
    )
    return X
end

# As a tensor not an action -> for now just matrix representation / tensor.
raw"""
    get_derivative(M, E, vbo::VectorbundleObjective, p)
    get_derivative(P::VectorBundleManoptProblem, p)

    Evaluate the vector field ``F'(p): T_p\mathcal M → T_{F(p)}\mathcal E`` at ``p``
    in a matrix form (TODO?? (a) matrix, (b) matrix action (c) something nice for Q?)
"""
function get_derivative(M, E, vbo::VectorbundleObjective, p)
    return vbo.derivative!!(M, p)
end
function get_derivative(vpb::VectorbundleManoptProblem, p)
    return get_derivative(
        get_manifold(vpb), get_vectorbundle(vpb), get_objective(vpb, true), p
    )
end

# As a tensor not an action -> for now just matrix representation / tensor.
raw"""
    get_connection_map(E, vbo::VectorbundleObjective, q)
    get_connection_map(vbp::VectorbundleManoptProblem, q)

Returns in matrix form the connection map ``Q_q: T_q\mathcal E → E_{π(q)}``
"""
function get_connection_map(E, vbo::VectorbundleObjective, q)
    return vbo.connection_map!!(E, q)
end
function get_connection_map(vbp::VectorbundleManoptProblem, q)
    return get_connection_map(get_vectorbundle(vbp), get_objective(vbp, true), q)
end

raw"""
    get_submersion(M, p)

    ```math
    c: ℝ^n → ℝ
    ```

    returns the submersion at point ``p`` which defines the manifold
    ``\mathcal M = \{p \in \bbR^n : c(p) = 0 \}``
"""
function get_submersion(M::AbstractManifold, p) end

raw"""
    get_submersion_derivative(M,p)

    returns the derivative ``c'(p) : T_p\mathcal{M} \to \mathcal R^{n-d}`` of the submersion at point ``p`` which defines the manifold in matrix form
"""
function get_submersion_derivative(M::AbstractManifold, p) end

@doc raw"""
    vectorbundle_newton(M, E, F, F_prime, Q, p; kwargs...)
    vectorbundle_newton(M, E, vbo p0; kwargs...)
    vectorbundle_newton!(M, E, F, F_prime, Q, p; kwargs...)
    vectorbundle_newton(M, E, vbo, p0; kwargs...)

Peform the vector bundle newon method on the vector bundle `E` over the manifold `M`
for `F` and `F_prime` using the connection map `Q`.
The point `p` denotes the start point. The algorithm can be run in-place of `p`.

You can also provide an [`VectorBundleObjective`](@ref) containing `F`, ``F'`` and ``Q``.
"""
vectorbundle_newton(M::AbstractManifold, E::AbstractManifold, args...; kwargs...) #replace type of E with VectorBundle once this is available in ManifoldsBase

function vectorbundle_newton(
    M::AbstractManifold, E::AbstractManifold, F, F_prime, Q, p; kwargs...
)
    q = copy(M, p)
    return vectorbundle_newton!(M, E, F, F_prime, Q, q; kwargs...)
end
function vectorbundle_newton(
    M::AbstractManifold, E::AbstractManifold, vbo::VectorbundleObjective, p; kwargs...
)
    q = copy(M, p)
    return vectorbundle_newton!(M, E, vbo, q; kwargs...)
end
function vectorbundle_newton!(
    M::AbstractManifold,
    E::AbstractManifold,
    F,
    F_prime,
    Q,
    p;
    #p_trial,
    #same_point;
    evaluation=AllocatingEvaluation(),
    kwargs...,
)
    vbo = VectorbundleObjective(F, F_prime, Q; evaluation=evaluation)
    return vectorbundle_newton!(M, E, vbo, p; evaluation=evaluation, kwargs...)
end
function vectorbundle_newton!(
    M::AbstractManifold,
    E::AbstractManifold,
    vbo::O,
    p::P;
    #p_trial::P2,
   # same_point::Bool;
    evaluation=AllocatingEvaluation(),
    sub_problem::Pr=nothing, #TODO: find/implement good default solver
    sub_state::Op=nothing, #TODO: find/implement good default solver
    X::T=zero_vector(M, p),
    retraction_method::RM=default_retraction_method(M, typeof(p)),
    stopping_criterion::SC=StopAfterIteration(1000),
    stepsize::Union{Stepsize,ManifoldDefaultsFactory}=default_stepsize(
        M, VectorbundleNewtonState
    ),
    vector_transport_method::VTM=default_vector_transport_method(
        E, typeof(get_bundle_map(M, E, vbo, p)),
    ),
    kwargs...,
) where {
    P,
    #P2,
    T,
    Pr,
    O<:Union{AbstractDecoratedManifoldObjective,VectorbundleObjective},
    Op,
    RM<:AbstractRetractionMethod,
    SC<:StoppingCriterion,
    S<:Stepsize,
    VTM<:AbstractVectorTransportMethod,
}
    # Once we have proper defaults, these checks should be removed
    isnothing(sub_problem) && error("Please provide a sub_problem")
    isnothing(sub_state) && error("Please provide a sub_state")
    dvbo = decorate_objective!(M, vbo; kwargs...)
    vbp = VectorbundleManoptProblem(M, E, dvbo)
    vbs = VectorbundleNewtonState(
        M,
        E,
        get_objective(vbo).bundle_map!!, #This is a bit of a too concrete access, maybe improve
        p,
        #p_trial,
       # same_point,
        sub_problem,
        sub_state;
        X=X,
        retraction_method=retraction_method,
        stopping_criterion=stopping_criterion,
        stepsize=_produce_type(stepsize, M),
        vector_transport_method=vector_transport_method,
    )
    dvbs = decorate_state!(vbs; kwargs...)
    solve!(vbp, dvbs)
    return get_solver_return(get_objective(vbp), dvbs)
end

function initialize_solver!(::VectorbundleManoptProblem, s::VectorbundleNewtonState)
    return s
end

function step_solver!(mp::VectorbundleManoptProblem, s::VectorbundleNewtonState, k)
    # compute Newton direction
    #println("Hallo 1")
    E = get_vectorbundle(mp) # vector bundle (codomain of F)
    o = get_objective(mp)
    # We need a representation of the equation system (use basis of tangent spaces or constraint representation of the tangent space -> augmented system)

    # TODO: pass parameters to sub_state
    # set_iterate!(s.sub_state, get_manifold(s.sub_problem), zero_vector(N, q)) Set start point x0
    #s.is_same = true
    set_manopt_parameter!(s.sub_problem, :Manifold, :Basepoint, s.p)

    set_iterate!(s.sub_state, get_manifold(s.sub_problem), zero_vector(get_manifold(s.sub_problem), s.p))
    #set_iterate!(s.sub_state, get_manifold(mp), zero_vector(get_manifold(mp), s.p))
    s.is_same = true
    solve!(s.sub_problem, s.sub_state)
    s.X = get_solver_result(s.sub_state)
    s.is_same= false

    step = s.stepsize(mp, s, k)
    s.is_same = true
    # retract
    retract!(get_manifold(mp), s.p, s.p, s.X, step, s.retraction_method)
    s.p_trial = copy(get_manifold(mp),s.p)
    s.is_same = true
    return s
end

function step_solver!(
    mp::VectorbundleManoptProblem,
    s::VectorbundleNewtonState{P,T,PR,AllocatingEvaluation},
    k,
) where {P,T,PR}
    # compute Newton direction
    #println("Hallo 2")
    E = get_vectorbundle(mp) # vector bundle (codomain of F)
    o = get_objective(mp)
    # We need a representation of the equation system (use basis of tangent spaces or constraint representation of the tangent space -> augmented system)
    s.is_same = true
    s.X = s.sub_problem(mp, s, k)
    s.is_same= false
   # println(s.p)
    step = s.stepsize(mp, s, k)
    s.is_same = true
    #println(s.p)
    # retract
    #println("norm Newton direction=", norm(s.X))
    #println("stepsize=", step)
    retract!(get_manifold(mp), s.p, s.p, s.X, step, s.retraction_method)
    s.p_trial = copy(get_manifold(mp),s.p)
    s.is_same = true
    return s
end

function step_solver!(
    mp::VectorbundleManoptProblem, s::VectorbundleNewtonState{P,T,PR,InplaceEvaluation}, k
) where {P,T,PR}
#println("HAllo 3")
    # compute Newton direction
    E = get_vectorbundle(mp) # vector bundle (codomain of F)
    o = get_objective(mp)
    # We need a representation of the equation system (use basis of tangent spaces or constraint representation of the tangent space -> augmented system)
    #s.is_same = true
    s.sub_problem(mp, s.X, s, k)
    #s.is_same = false
    step = s.stepsize(mp, s, k)
    # retract
    retract!(get_manifold(mp), s.p, s.p, s.X, step, s.retraction_method)
    s.p_trial = copy(s.p)
    #s.is_same = true
    return s
end