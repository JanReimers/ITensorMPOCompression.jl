using ITensors
using ITensorMPOCompression
using Revise
using Test

include("../test/hamiltonians.jl")


function runtest()
    N=5
    NNN=4
    hx=0.5
    #eps=1e-15
    sites = siteinds("SpinHalf", N)
    psi=randomMPS(sites)
    H=make_transIsing_MPO(sites,NNN,hx,pbc=true) 
    E0=inner(psi',to_openbc(H),psi)
    @show E0

    canonical!(H)
    
    E1=inner(psi',to_openbc(H),psi)
    @test abs(E0-E1)<1e-14
    

    
    
end

using Printf
Base.show(io::IO, f::Float64) = @printf(io, "%1.3f", f)
println("-----------Start--------------")
runtest()