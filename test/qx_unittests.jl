using ITensors
using ITensorMPOCompression
using Test
using Printf

#
# Single index tests
#
function test_qx(::Type{ElT},qx::Function,M::Int64,N::Int64,pos::Bool) where {ElT<:Number}
    ir=Index(M,"row")
    ic=Index(N,"col")
    A=randomITensor(ElT,ir,ic)
    Q,LR=qx(A,ir;positive=pos)
    norm(A-Q*LR)
end

function test_xq(::Type{ElT},xq::Function,M::Int64,N::Int64,pos::Bool) where {ElT<:Number}
    ir=Index(M,"row")
    ic=Index(N,"col")
    A=randomITensor(ElT,ir,ic)
    LR,Q=xq(A,ir;positive=pos)
    norm(A-LR*Q)
end

@testset "QR decomposition, single index" begin
    eps=1e-14
    M,N=5,5
    M1,N1=10,10
    @test test_qx(Float64   ,qr,M ,N,false)<eps
    @test test_qx(Float64   ,qr,M ,N1,false)<eps
    @test test_qx(Float64   ,qr,M1,N1,false)<eps
    @test test_qx(Float64   ,qr,M ,N ,true )<eps
    @test test_qx(Float64   ,qr,M ,N1,true )<eps
    @test test_qx(Float64   ,qr,M1,N1,true )<eps
    @test test_qx(ComplexF64,qr,M ,N ,false)<eps
    @test test_qx(ComplexF64,qr,M ,N1,false)<eps
    @test test_qx(ComplexF64,qr,M1,N1,false)<eps
    @test test_qx(ComplexF64,qr,M ,N ,true )<eps
    @test test_qx(ComplexF64,qr,M ,N1,true )<eps
    @test test_qx(ComplexF64,qr,M1,N1,true )<eps
end

@testset "QL decomposition, single index" begin
    eps=1e-14
    M,N=5,5
    M1,N1=10,10
    @test test_qx(Float64   ,ql,M ,N,false)<eps
    @test test_qx(Float64   ,ql,M ,N1,false)<eps
    @test test_qx(Float64   ,ql,M1,N1,false)<eps
    @test test_qx(Float64   ,ql,M ,N ,true )<eps
    @test test_qx(Float64   ,ql,M ,N1,true )<eps
    @test test_qx(Float64   ,ql,M1,N1,true )<eps
    @test test_qx(ComplexF64,ql,M ,N ,false)<eps
    @test test_qx(ComplexF64,ql,M ,N1,false)<eps
    @test test_qx(ComplexF64,ql,M1,N1,false)<eps
    @test test_qx(ComplexF64,ql,M ,N ,true )<eps
    @test test_qx(ComplexF64,ql,M ,N1,true )<eps
    @test test_qx(ComplexF64,ql,M1,N1,true )<eps
end

@testset "LQ decomposition, single index" begin
    eps=1e-14
    M,N=5,5
    M1,N1=10,10
    @test test_xq(Float64   ,lq,M ,N,false)<eps
    @test test_xq(Float64   ,lq,M ,N1,false)<eps
    @test test_xq(Float64   ,lq,M1,N1,false)<eps
    @test test_xq(Float64   ,lq,M ,N ,true )<eps
    @test test_xq(Float64   ,lq,M ,N1,true )<eps
    @test test_xq(Float64   ,lq,M1,N1,true )<eps
    @test test_xq(ComplexF64,lq,M ,N ,false)<eps
    @test test_xq(ComplexF64,lq,M ,N1,false)<eps
    @test test_xq(ComplexF64,lq,M1,N1,false)<eps
    @test test_xq(ComplexF64,lq,M ,N ,true )<eps
    @test test_xq(ComplexF64,lq,M ,N1,true )<eps
    @test test_xq(ComplexF64,lq,M1,N1,true )<eps
end

@testset "RQ decomposition, single index" begin
    eps=1e-14
    M,N=5,5
    M1,N1=10,10
    @test test_xq(Float64   ,rq,M ,N,false)<eps
    @test test_xq(Float64   ,rq,M ,N1,false)<eps
    @test test_xq(Float64   ,rq,M1,N1,false)<eps
    @test test_xq(Float64   ,rq,M ,N ,true )<eps
    @test test_xq(Float64   ,rq,M ,N1,true )<eps
    @test test_xq(Float64   ,rq,M1,N1,true )<eps
    @test test_xq(ComplexF64,rq,M ,N ,false)<eps
    @test test_xq(ComplexF64,rq,M ,N1,false)<eps
    @test test_xq(ComplexF64,rq,M1,N1,false)<eps
    @test test_xq(ComplexF64,rq,M ,N ,true )<eps
    @test test_xq(ComplexF64,rq,M ,N1,true )<eps
    @test test_xq(ComplexF64,rq,M1,N1,true )<eps
end

#
#  Test multiple indicies using MPO matrices
#
@testset "QR,QL,LQ,RQ decomposition fo MPO matrices" begin
    N=5
    NNN=4
    hx=0.5
    eps=2e-15
    sites = siteinds("SpinHalf", N)
    H=make_transIsing_MPO(sites,NNN,hx)
    W=H[2]
    d,n,r,c=parse_links(W)

    Lind=noncommoninds(inds(W),c)
    Rind=noncommoninds(inds(W),r)

    Q,R=qr(W,Lind;positive=true)
    iqr=commonindex(Q,R)
    Id=Q*prime(Q,iqr)
    Idq=delta(iqr,iqr')
    @test norm(Id-Idq)<eps
    @test norm(W-Q*R)<eps

    Q,L=ql(W,Lind;positive=true)
    iql=commonindex(Q,L)
    Id=Q*prime(Q,iql)
    Idq=delta(iql,iql')
    @test norm(Id-Idq)<eps
    @test norm(W-Q*L)<eps

    L,Q=lq(W,Rind;positive=true)
    iql=commonindex(Q,L)
    Id=Q*prime(Q,iql)
    Idq=delta(iql,iql')
    @test norm(Id-Idq)<eps
    @test norm(W-L*Q)<eps

    R,Q=rq(W,Rind;positive=true)
    iql=commonindex(Q,R)
    Id=Q*prime(Q,iql)
    Idq=delta(iql,iql')
    @test norm(Id-Idq)<eps
    @test norm(W-R*Q)<eps
end


#using Printf
#Base.show(io::IO, f::Float64) = @printf(io, "%1.3f", f)
#println("-----------Start--------------")

@testset "QR,QL,LQ,RQ decomposition with rank revealing" begin
    N=10
    NNN=6
    hx=0.5
    eps=2e-15
    sites = siteinds("SpinHalf", N)
    #
    #  use lower tri MPO to get some zero pivots for QL and RQ.
    #
    H=make_transIsing_MPO(sites,NNN,hx,lower)
    W=H[2]
    d,n,r,c=parse_links(W)

    Lind=noncommoninds(inds(W),c)
    Rind=noncommoninds(inds(W),r)
    @assert dim(c)==dim(r)
    #
    #  RQ decomp
    #
    R,Q=rq(W,Rind;positive=true,rank=true)
    iq=commonindex(Q,R)
    @printf "RQ decomposition %4i rows were removed from R\n" dim(c)-dim(iq)
    Id=Q*prime(Q,iq)
    Idq=delta(iq,iq')
    @test norm(Id-Idq)<eps
    @test norm(W-R*Q)<eps
    #
    #  QL decomp
    #
    Q,L=ql(W,Rind;positive=true,rank=true)
    iq=commonindex(Q,L)
    @printf "QL decomposition %4i rows were removed from L\n" dim(c)-dim(iq)
    Id=Q*prime(Q,iq)
    Idq=delta(iq,iq')
    @test norm(Id-Idq)<eps
    @test norm(W-L*Q)<eps    
    
    #
    #  use upper tri MPO to get some zero pivots for LQ and QR.
    #
    H=make_transIsing_MPO(sites,NNN,hx,upper)
    W=H[2]
    d,n,r,c=parse_links(W)

    Lind=noncommoninds(inds(W),c)
    Rind=noncommoninds(inds(W),r)
    @assert dim(c)==dim(r)

    #
    #  QR decomp
    #
    Q,R=ITensorMPOCompression.qr(W,Rind;positive=true,rank=true)
    iq=commonindex(Q,R)
    @printf "QR decomposition %4i rows were removed from R\n" dim(c)-dim(iq)
    Id=Q*prime(Q,iq)
    Idq=delta(iq,iq')
    @test norm(Id-Idq)<eps
    @test norm(W-R*Q)<eps
    #
    #  LQ decomp
    #
    L,Q=lq(W,Rind;positive=true,rank=true)
    iq=commonindex(Q,L)
    @printf "LQ decomposition %4i rows were removed from L\n" dim(c)-dim(iq)
    Id=Q*prime(Q,iq)
    Idq=delta(iq,iq')
    @test norm(Id-Idq)<eps
    @test norm(W-L*Q)<eps

    

end
 #= 
@testset "QR,QL,LQ,RQ decomposition for block sparse matrices" begin
    N=5
    NNN=2
    Dw=3
    hx=0.0 #can't make and sx op with QNs in play
    ul=lower
    lr=left
    ms=matrix_state(ul,lr)

    rowq=Index(QN("Sz",0)=>Dw;dir=ITensors.In,tags="Link,l=1") #link index with qn's
    colq=Index(QN("Sz",0)=>Dw;dir=ITensors.Out,tags="Link,l=2")
    sites = siteinds("S=1/2",N;conserve_qns=true) #sites with qn's
    H=make_transIsing_MPO(sites,NNN,hx,ul)
    W=H[2]
    pprint(W,1e-14)
    # Q,R,lq=block_qx(W,ul;orth=lr)
    
    off=V_offsets(ms)
    Vblock=getV(W,off)
    Rind=filterinds(Vblock,tags="l=2")
    Linds=noncommoninds(Vblock,Rind)
    Vd=dense(Vblock)
    Qd,Ld,iq=ql(Vd,Linds;positive=true,epsrr=0.0)
    set_scale!(Ld,Qd,off) #rescale so the L(n,n)==1.0
    pprint(Qd,1e-14)
    # @show Qd Ld

    # Vt=NDTensors.tensor(Vblock)
    # for b in eachnzblock(Vt)
    #     bl=NDTensors.blockview(Vt, b)
    #     @show Vt
    # end
    Q,L,iq=ql(Vblock,Linds;positive=true,epsrr=0.0)
    # U,s,V,iu,iv=svd(Vblock,Linds)
    #@show U V
end =#