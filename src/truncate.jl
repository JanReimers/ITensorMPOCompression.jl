
using LinearAlgebra
using Printf

function getInverse(U::ITensor,s::ITensor,V::ITensor)::ITensor
    as=LinearAlgebra.diag(array(s))
    asinv=Vector(as)
    for ia in 1:length(asinv) asinv[ia]=1.0/asinv[ia] end
    sinv=diagITensor(eltype(asinv),asinv,inds(s))
    Minv=dag(V)*dag(sinv)*dag(U)
    return Minv
end

#
# Solve RL=M*RL_prime we only need to solve the last few columns to the right of
# the unit matrix inside RL_prime
#
function SolveRLprime(RL::ITensor,RL_prime::ITensor,U::ITensor,s::ITensor,V::ITensor,iq::Index,im::Index,ms::matrix_state)::ITensor
    Minv=getInverse(U,s,V)
    ic1=noncommonind(RL_prime,im) #RL_prime col index
    ic2=noncommonind(RL      ,iq) #RL       col index
    @assert ic1==ic2
    @assert dim(iq)==dim(im)
    #eps=1e-14
    #@show "RL="
    #pprint(iq,RL,ic1,eps)
    #@show "RL_prime="
    #pprint(im,RL_prime,ic1,eps)
    Dm,Dc=dim(im),dim(ic1)
    @assert Dm>2
    @assert Dc>Dm
    imm=filterinds(Minv,tags=tags(im))[1]
    iqm=filterinds(Minv,tags=tags(iq))[1]
    @assert dim(imm)==dim(im)-2
    @assert dim(iqm)==dim(iq)-2
    icm=Index(Dc-Dm,tags(ic1))
    R2=ITensor(0.0,iqm,icm)
    j1_offset=1
    if ms.ul==lower
        j2_offset=Dm-1
    else #upper
        j2_offset=1
    end
    #@show ms Dm j2_offset

    for j2 in eachindval(icm)
        for j1 in eachindval(iqm)
            R2[j1,j2]=RL[iq=>j1.second+j1_offset,ic1=>j2.second+j2_offset]
        end
    end
    # @show "R2="
    # pprint(iqm,R2,icm,1e-14)
    R2_prime=Minv*R2
    
    #@show inds(R2_prime)
    #pprint(imm,R2_prime,icm,eps)
    for j2 in eachindval(icm)
        for j1 in eachindval(imm)
            RL_prime[im=>j1.second+j1_offset,ic1=>j2.second+j2_offset]=R2_prime[j1,j2]
        end
    end
    #pprint(im,RL_prime,ic1,eps)

    return RL_prime
end
#
#  Compress one site
#
function truncate(W::ITensor,ul::reg_form;kwargs...)::Tuple{ITensor,ITensor,bond_spectrum}
    d,n,r,c=parse_links(W) # W[l=$(n-1)l=$n]=W[r,c]
    lr::orth_type=get(kwargs, :orth, right)
    ms=matrix_state(ul,lr)
    eps=1e-14 #relax used for testing upper/lower/regular-form etc.
    # establish some tag strings then depend on lr.
    (tsvd,tuv,tln) = lr==left ? ("qx","u","l=$n") : ("m","v","l=$(n-1)")

#
# Block repecting QR/QL/LQ/RQ factorization.  RL=L or R for upper and lower.
# here we purposely turn off rank reavealing feature (epsrr=0.0) to (mostly) avoid
# horizontal rectangular RL matricies which are hard to handle accurately.
#
    Q,RL,lq=block_qx(W,ul;epsrr=0.0,kwargs...) #left Q[r,qx], RL[qx,c] - right RL[r,qx] Q[qx,c]
    ITensors.@debug_check begin
        if order(Q)==4
            @assert is_canonical(Q,ms,eps)
            @assert is_regular_form(Q,ul,eps)
        end
    end
#
#  Factor RL=M*L' (left/lower) = L'*M (right/lower) = M*R' (left/upper) = R'*M (right/upper)
#
    c=noncommonind(RL,lq) #if size changed the old c is not lnger valid
    M,RL_prime,im,RLnz=getM(RL,ms,eps) #left M[lq,im] RL_prime[im,c] - right RL_prime[r,im] M[im,lq]
#
#  At last we can svd and compress M using epsSVD as the cutoff.
#    
    min_cutoff=1e-12
    cutoff=get(kwargs,:cutoff,min_cutoff)
    cutoff=cutoff<min_cutoff ? min_cutoff : cutoff
    kwargs=add_or_replace(kwargs,:cutoff,cutoff) #make sure cutoff is not zero.
    isvd=findinds(M,tsvd)[1] #decide the left index
    U,s,V=svd(M,isvd;kwargs...) # ns sing. values survive compression
    ns=dim(inds(s)[1])

    spectrum=bond_spectrum(s,n)
    #@show diag(array(s))
    #
    #  If RL is rectangular we need to solve RL=M*RL_prime for RL_prime
    #  since we know UsV anyway we can calculate M^-1=dag(V)*1.0/s*dag(U)
    #
    if ns>0 && RLnz
        @show "fixing RL_prime" 
        RL_prime=SolveRLprime(RL,RL_prime,U,s,V,lq,im,ms)
    end
    Mplus=grow(M,lq,im)
    D=RL-Mplus*RL_prime
    if norm(D)>get(kwargs, :cutoff, 1e-14)
        @printf "High normD(D)=%.1e min(s)=%.1e \n" norm(D) Base.min(diag(array(s))...)
    end

    luv=Index(ns+2,"Link,$tuv") #link for expanded U,US,V,sV matricies.
    if lr==left
        ITensors.@debug_check begin
            @assert is_upper_lower(lq,RL      ,c,ul,eps)
        end
        RL=grow(s*V,luv,im)*RL_prime #RL[l=n,u] dim ns+2 x Dw2
        W=Q*grow(U,lq,luv) #W[l=n-1,u]
    else # right
        ITensors.@debug_check begin
            @assert is_upper_lower(r,RL      ,lq,ms.ul,eps)
        end
        RL=RL_prime*grow(U*s,im,luv) #RL[l=n-1,v] dim Dw1 x ns+2
        W=grow(V,lq,luv)*Q #W[l=n-1,v]
    end
    replacetags!(RL,tuv,tln) #RL[l=n,l=n] sames tags, different id's and possibly diff dimensions.
    replacetags!(W ,tuv,tln) #W[l=n-1,l=n]
    ITensors.@debug_check begin
        @assert is_regular_form(W,ul,eps)
        @assert is_canonical(W,ms,eps)
    end
    return W,RL,spectrum
end

@doc """
    truncate!(H::MPO)

Compress an MPO using block respecting SVD techniques as described in 
> *Daniel E. Parker, Xiangyu Cao, and Michael P. Zaletel Phys. Rev. B 102, 035147*

# Arguments
- `H` MPO for decomposition. If H is not already in the correct canonical form for compression, it will automatically be put into the correct form prior to compression.

# Keywords
- `orth::orth_type = left` : choose `left` or `right` canonical form for the final output. 
- `cutoff::Float64 = 1e-14` : Using a `cutoff` allows the SVD algorithm to truncate as many states as possible while still ensuring a certain accuracy. 
- `maxdim::Int64` : If the number of singular values exceeds `maxdim`, only the largest `maxdim` will be retained.
- `mindim::Int64` : At least `mindim` singular values will be retained, even if some fall below the cutoff

# Example
```julia
julia> using ITensors
julia> using ITensorMPOCompression
julia> N=10; #10 sites
julia> NNN=7; #Include up to 7th nearest neighbour interactions
julia> sites = siteinds("S=1/2",N);
#
# This makes H directly, bypassing autoMPO.  (AutoMPO is too smart for this
# demo, it makes maximally reduced MPOs right out of the box!)
#
julia> H=make_transIsing_MPO(sites,NNN);
#
#  Make sure we have a regular form or truncate! won't work.
#
julia> is_lower_regular_form(H)==true
true

#
#  Now we can truncate with defaults of left orthogonal cutoff=1e-14.
#  truncate! returns the spectrum of singular values at each bond.  The largest
#  singular values are remaining well under control.  i.e. no sign of divergences.
#
julia> truncate!(H)
9-element Vector{bond_spectrum}:
 bond_spectrum([0.307], 1)
 bond_spectrum([0.354, 0.035], 2)
 bond_spectrum([0.375, 0.045, 0.021], 3)
 bond_spectrum([0.385, 0.044, 0.026, 0.018], 4)
 bond_spectrum([0.388, 0.043, 0.031, 0.019, 0.001], 5)
 bond_spectrum([0.385, 0.044, 0.026, 0.018], 6)
 bond_spectrum([0.375, 0.045, 0.021], 7)
 bond_spectrum([0.354, 0.035], 8)
 bond_spectrum([0.307], 9)

julia> pprint(H[2])
I 0 0 0 
S S S 0 
0 S S I 

#
#  We can see that bond dimensions have been drastically reduced.
#
julia> get_Dw(H)
9-element Vector{Int64}: 3 4 5 6 7 6 5 4 3

julia> is_lower_regular_form(H)==true
true

julia> is_orthogonal(H,left)==true
true

```
"""
function truncate!(H::MPO;kwargs...)::bond_spectrums
    #@printf "---- start compress ----\n"
    #
    # decide left/right and upper/lower
    #
    lr::orth_type=get(kwargs, :orth, left)
    kwargs=add_or_replace(kwargs,:orth,lr) #if lr is not yet in kwargs, we need to stuff in there
    (bl,bu)=detect_regular_form(H)
    if !(bl || bu)
        throw(ErrorException("truncate!(H::MPO), H must be in either lower or upper regular form"))
    end
    @assert !(bl && bu)
    ul::reg_form = bl ? lower : upper #if both bl and bu are true then something is seriously wrong
    #
    # Now check if H required orthogonalization
    #
    ms=matrix_state(ul,lr)
    if !is_canonical(H,mirror(ms))
        epsrr=get(kwargs,:epsrr,1e-12)
        epsrr= epsrr==0 ? 1e-12 : epsrr #0.0 not allwed here.
        orthogonalize!(H,epsrr=epsrr,orth=mirror(lr)) #TODO why fail if spec ul here??
    end
    N=length(H)
    ss=bond_spectrums(undef,N-1)
    if lr==left
        rng=1:1:N-1 #sweep left to right
        link_offest=0
    else #right
        rng=N:-1:2 #sweep right to left
        link_offest=-1
    end
    for n in rng 
        nn=n+rng.step #index to neighbour
        W,RL,s=truncate(H[n],ul;kwargs...)
        H[n]=W
        H[nn]=RL*H[nn]
        is_regular_form(H[nn],ms.ul)
        ss[n+link_offest]=s
    end
    return ss
end