
@doc """
    truncate!(H::MPO)

Compress an MPO using block respecting SVD techniques as described in 
> *Daniel E. Parker, Xiangyu Cao, and Michael P. Zaletel Phys. Rev. B 102, 035147*

# Arguments
- `H` MPO for decomposition. If `H` is not already in the correct canonical form for compression, it will automatically be put into the correct form prior to compression.

# Keywords
- `orth::orth_type = left` : choose `left` or `right` canonical form for the final output. 
- `cutoff::Float64 = 0.0` : Using a `cutoff` allows the SVD algorithm to truncate as many states as possible while still ensuring a certain accuracy. 
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
julia> @show truncate!(H);
site  Ns   max(s)     min(s)    Entropy  Tr. Error
   1    1  0.30739   3.07e-01   0.22292  0.00e+00
   2    2  0.35392   3.49e-02   0.26838  0.00e+00
   3    3  0.37473   2.06e-02   0.29133  0.00e+00
   4    4  0.38473   1.77e-02   0.30255  0.00e+00
   5    5  0.38773   7.25e-04   0.30588  0.00e+00
   6    4  0.38473   1.77e-02   0.30255  0.00e+00
   7    3  0.37473   2.06e-02   0.29133  0.00e+00
   8    2  0.35392   3.49e-02   0.26838  0.00e+00
   9    1  0.30739   3.07e-01   0.22292  0.00e+00

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

julia> isortho(H,left)==true
true

```
"""
function truncate(
  Ŵrf::reg_form_Op, lr::orth_type; kwargs...
)::Tuple{reg_form_Op,ITensor,Spectrum}
  @mpoc_assert Ŵrf.ul==lower
  ilf = forward(Ŵrf, lr)
  #   l=n-1   l=n        l=n-1  l=n  l=n
  #   ------W----   -->  -----Q-----R-----
  #           ilf               iqx   ilf
  Q̂, R, iqx = ac_qx(Ŵrf, lr; qprime=true, kwargs...) #left Q[r,qx], R[qx,c] - right R[r,qx] Q[qx,c]
  @checkflux(Q̂.W)
  @checkflux(R)
  @mpoc_assert dim(ilf) == dim(iqx) #Rectanuglar not allowed
  #
  #  Factor RL=M*L' (left/lower) = L'*M (right/lower) = M*R' (left/upper) = R'*M (right/upper)
  #  M will be returned as a Dw-2 X Dw-2 interior matrix.  M_sans in the Parker paper.
  #
  Dw = dim(iqx)
  M = R[dag(iqx) => 2:(Dw - 1), ilf => 2:(Dw - 1)]
  M = replacetags(M, tags(ilf), "Link,m"; plev=0)
  #  l=n'    l=n           l=n'   m      l=n
  #  ------R----   --->   -----M------R'----
  #  iqx'    ilf           iqx'   im     ilf
  R⎖, im = build_R⎖(R, iqx, ilf) #left M[lq,im] RL_prime[im,c] - right RL_prime[r,im] M[im,lq]
  #  
  #  svd decomp M. 
  #    
  isvd = inds(M; tags=tags(iqx))[1] #decide the backward index for svd.  Works for both sweep directions.
  U, s, V, spectrum, iu, iv = svd(M, isvd; kwargs...) # ns sing. values survive compression
  #@show diag(array(s))
  #
  #  Now recontrsuct R, and W in the truncated space.
  #
  iup = redim(iu, 1, 1, space(iqx))
  R = grow(s * V, iup, im) * R⎖ #RL[l=n,u] dim ns+2 x Dw2
  Uplus = grow(U, dag(iqx), dag(iup))
  Uplus = noprime(Uplus, iqx)
  Ŵrf = Q̂ * Uplus #W[l=n-1,u]

  R = replacetags(R, "Link,u", tags(ilf)) #RL[l=n,l=n] sames tags, different id's and possibly diff dimensions.
  Ŵrf = replacetags(Ŵrf, "Link,u", tags(ilf)) #W[l=n-1,l=n]
  check(Ŵrf)
  return Ŵrf, R, spectrum
end

function ITensors.truncate!(
  H::reg_form_MPO, lr::orth_type; eps=1e-14, kwargs...
)::bond_spectrums
  #Two sweeps are essential for avoiding rectangular R in site truncate.
  if !isortho(H)
    ac_orthogonalize!(H, lr; eps=eps, kwargs...)
    ac_orthogonalize!(H, mirror(lr); eps=eps, kwargs...)
  end
  gauge_fix!(H)
  ss = bond_spectrums(undef, 0)
  rng = sweep(H, lr)
  for n in rng
    nn = n + rng.step
    H[n], R, s = truncate(H[n], lr; kwargs...)
    H[nn] *= R
    push!(ss, s)
  end
  H.rlim = rng.stop + rng.step + 1
  H.llim = rng.stop + rng.step - 1
  return ss
end

@doc """
    truncate!(H::InfiniteMPO;kwargs...)

Truncate a `CelledVector` representation of an infinite MPO as described in section VII and Alogrithm 5 of:
> Daniel E. Parker, Xiangyu Cao, and Michael P. Zaletel Phys. Rev. B 102, 035147
It is not nessecary (or recommended) to call the `orthogonalize!` function prior to calling `truncate!`. The `truncate!` function will do this automatically.  This is because the truncation process requires the gauge transform tensors resulting from left orthogonalizing an already right orthogonalized iMPO (or converse).  So it is better to do this internally in order to be sure the correct gauge transforms are used.

# Arguments
- H::InfiniteMPO which is a `CelledVector` of MPO matrices. `CelledVector` and `InfiniteMPO` are defined in the `ITensorInfiniteMPS` module.

# Keywords
- `orth::orth_type = left` : choose `left` or `right` canonical form for the output
- `rr_cutoff::Float64 = -1.0` : cutoff for rank revealing QX which removes zero pivot rows and columns. 
   All rows with max(abs(R[r,:]))<rr_cutoff are considered zero and removed. rr_cutoff=1.0 indicate no rank reduction.
- `cutoff::Float64 = 0.0` : Using a `cutoff` allows the SVD algorithm to truncate as many states as possible while still ensuring a certain accuracy. 
- `maxdim::Int64` : If the number of singular values exceeds `maxdim`, only the largest `maxdim` will be retained.
- `mindim::Int64` : At least `mindim` singular values will be retained, even if some fall below the cutoff
   
# Returns
- Vector{ITensor} with the diagonal gauge transforms between the input and output iMPOs
- a `bond_spectrums` object which is a `Vector{Spectrum}`

# Example
```
julia> using ITensors, ITensorMPOCompression, ITensorInfiniteMPS
julia> initstate(n) = "↑";
julia> sites = infsiteinds("S=1/2", 1;initstate, conserve_szparity=false)
1-element CelledVector{Index{Int64}, typeof(translatecelltags)}:
 (dim=2|id=224|"S=1/2,Site,c=1,n=1")
julia> H=make_transIsing_iMPO(sites,7);
julia> get_Dw(H)[1]
30
julia> Ss,spectrum=truncate!(H;rr_cutoff=1e-15,cutoff=1e-15);
julia> get_Dw(H)[1]
9
julia> pprint(H[1])
I 0 0 0 0 0 0 0 0 
S S S S S S S S 0 
S S S S S S S S 0 
S S S S S S S S 0 
S S S S S S S S 0 
S S S S S S S S 0 
S S S S S S S S 0 
S S S S S S S S 0 
0 S S S S S S S I 
julia> @show spectrum
spectrum = 
site  Ns   max(s)     min(s)    Entropy  Tr. Error
   1    7  0.39565   1.26e-02   0.32644  1.23e-16

```
"""
function ITensors.truncate!(
  H::reg_form_iMPO, lr::orth_type; rr_cutoff=1e-14, kwargs...
)::Tuple{CelledVector{ITensor},bond_spectrums,Any}
  #@printf "---- start compress ----\n"
  #
  # Now check if H requires orthogonalization
  #
  # if isortho(H, lr)
  #   @warn "truncate!(iMPO), iMPO is already orthogonalized, but the truncate algorithm needs the gauge transform tensors." *
  #     "running orthongonalie!() again to get the gauge tranforms."
  # end
  ac_orthogonalize!(H, mirror(lr); cutoff=rr_cutoff, kwargs...)
  Hm = copy(H)
  Gs = ac_orthogonalize!(H, lr; cutoff=rr_cutoff, kwargs...)
  # @show get_Dw(Hm)
  # @show get_Dw(H)
  
  return truncate!(H, Hm, Gs, lr; kwargs...)
end

function ITensors.truncate!(
  H::reg_form_iMPO, Hm::reg_form_iMPO, Gs::CelledVector{ITensor}, lr::orth_type; kwargs...
)::Tuple{CelledVector{ITensor},bond_spectrums,Any}
  gauge_fix!(H)

  N = length(H)
  ss = bond_spectrums(undef, N)
  Ss = CelledVector{ITensor}(undef, N)
  for n in 1:N
    #prime the right index of G so that indices can be distinguished.
    #Ideally orthogonalize!() would spit out Gs that are already like this.
    igl = commonind(Gs[n], H[n].W)
    igr = noncommonind(Gs[n], igl)
    Gs[n] = replaceind(Gs[n], igr, prime(igr))
    #iln=linkind(H,n) #Link between Hn amd Hn+1
    iln = H[n].iright
    #           
    #  -----G[n-1]-----HR[n]-----   ==    -----HL[n]-----G[n]-----  
    #
    if lr == left
      @assert igl == iln
      # println("-----------------Left----------------------")
      igl = iln #right link of Hn is the left link of Gn
      U, Sp, V, spectrum = truncate(Gs[n], dag(igl); kwargs...)
      check(H[n])

      H[n] *= U
      H[n + 1] *= dag(U)
      Hm[n] *= dag(V)
      Hm[n + 1] *= V
      check(H[n])
      check(Hm[n])
    else
      # println("-----------------Right----------------------")
      igl = noncommonind(Gs[n], iln) #left link of Hn+1 is the right link Gn
      U, Sp, V, spectrum = truncate(Gs[n], igl; kwargs...)
      check(H[n])
      H[n] *= dag(V)
      H[n + 1] *= V
      Hm[n] *= U
      Hm[n + 1] *= dag(U)
      check(H[n])
      check(Hm[n])
    end

    Ss[n] = Sp
    ss[n] = spectrum
  end
  return Ss, ss, Hm
end

function truncate(G::ITensor, igl::Index; kwargs...)
  @mpoc_assert order(G) == 2
  igr = noncommonind(G, igl)
  @mpoc_assert tags(igl) != tags(igr) || plev(igl) != plev(igr) #Make sure subtensr can distinguish igl and igr
  M = G[igl => 2:(dim(igl) - 1), igr => 2:(dim(igr) - 1)]
  iml, = inds(M; plev=plev(igl)) #tags are the same, so plev is the only way to distinguish.
  U, s, V, spectrum, iu, iv = svd(M, iml; kwargs...)
  #
  # Build up U+, S+ and V+
  #
  iup = redim(iu, 1, 1, space(igl)) #Use redim to preserve QNs
  ivp = redim(iv, 1, 1, space(igr))
  #@show iu iup iv ivp igl s dense(s) U
  Up = grow(noprime(U), noprime(igl), dag(iup))
  Sp = grow(s, iup, ivp)
  Vp = grow(noprime(V), dag(ivp), noprime(igr))
  #
  #  But external link tags in so contractions with W[n] tensors will work.
  #
  Up=replacetags(Up, tags(iu), tags(igl))
  Sp=replacetags(Sp, tags(iu), tags(igl))
  Sp=replacetags(Sp, tags(iv), tags(igr))
  Vp=replacetags(Vp, tags(iv), tags(igr))
  #@mpoc_assert norm(dense(noprime(G))-dense(Up)*Sp*dense(Vp))<1e-12    #expensive!!!
  return Up, Sp, Vp, spectrum
end

#
#  Make sure indices are ordered and then convert to a matrix
#
function NDTensors.matrix(il::Index, T::ITensor, ir::Index)
  T1 = ITensors.permute(T, il, ir; allow_alias=true)
  return matrix(T1)
end
