#using Printf

function getspace(i::QNIndex,off::Int64)
    @mpoc_assert off==0 || off==1
    nb=nblocks(i)
    qnb=off==0 ? space(i)[nb] : space(i)[1]
    #@show off space(i)
    #@mpoc_assert blockdim(qnb)==1 TODO: get this working.
    return qn(qnb) 
end
function getspace(i::Index,off::Int64)
    return 1 
end
#
#  create a Vblock IndexRange using the supplied offset.
#
range(i::Index,offset::Int64) = i=>1+offset:dim(i)-1+offset
#
# functions for getting and setting V blocks required for block respecting QX and SVD
#
function getV(W::ITensor,off::V_offsets)::Tuple{ITensor, Union{QN,Int}}
    if order(W)==3
        w1=filterinds(inds(W),tags="Link")[1]
        return W[range(w1,off.o1)],getspace(w1,off.o1)
    elseif order(W)==4
        w1,w2=filterinds(inds(W),tags="Link")
        if dim(w1)==1
            return W[w1=>1:1,range(w2,off.o2)],getspace(w1,off.o1)
        elseif dim(w2)==1
            return W[range(w1,off.o1),w2=>1:1],getspace(w1,off.o1)
        else
            return W[range(w1,off.o1),range(w2,off.o2)],getspace(w1,off.o1)
        end
    else 
        @show inds(W)
        @error("getV(W::ITensor,off::V_offsets) Case with order(W)=$(order(W)) not supported.")
    end
end
# Handles W with only one link index
function setV1(W::ITensor,V::ITensor,iqx::Index,ms::matrix_state)::ITensor
    iwl,=filterinds(inds(W),tags="Link") #should be l=n, l=n-1
    ivl,=filterinds(inds(V),tags="Link") #should be qx and {l=n,l=n-1} depending on sweep direction
    @mpoc_assert inds(W,tags="Site")==inds(V,tags="Site")
    off=V_offsets(ms)
    @mpoc_assert(off.o1==off.o2)
    # 
    # W & V need to have the same Link tags as W1 for the assignments below to work.
    #
    W=replacetags(W,tags(iwl),tags(iqx))
    V=replacetags(V,tags(ivl),tags(iqx)) 
    iwl,=inds(W,tags=tags(iqx))
    #
    #  Make a new tensor to copy V and one row of W into
    #
    T=eltype(V)
    W1=ITensor(T(0.0),iqx,inds(W,tags="Site"))
    rc= off.o1==1 ? 1 : dim(iwl) #preserve row/col 1 or Dw
    rc1= off.o1==1 ? 1 : dim(iqx)
    W1[iqx=>rc1:rc1]=W[iwl=>rc:rc]
    W1[range(iqx,off.o1)]=V #Finally we can do the assingment of the V-block.
    return W1
end

#
#  This function is non trivial for 3 reasons:
#   1) V could have a truncted number of rows or columns as a result of rank revealing QX
#      W then has to be re-sized accordingly
#   2) If W gets resized we need to preserve particular rows/columns outside the Vblock from the old W.
#   3) V and W should have one common link index so we need to find those and pair them together. But we
#      need to match on tags&plev because dims are different so ID matching won't work. 
#
function setV(W::ITensor,V::ITensor,iqx::Index,ms::matrix_state)::ITensor
    if order(W)==3
        return setV1(W,V,iqx,ms) #Handle row/col vectors
    end
    #
    #  Deduce all link indices
    #
    @mpoc_assert order(W)==4
    wils=filterinds(inds(W),tags="Link") #should be l=n, l=n-1
    vils=filterinds(inds(V),tags="Link") #should be qx and {l=n,l=n-1} depending on sweep direction
    @mpoc_assert length(wils)==2
    @mpoc_assert length(vils)==2
    ivqx,=inds(V,tags="Link,qx") #get the qx index.  This is the one that can change size
    ivl=noncommonind(vils,ivqx)  #get the other link l=n index on V
    iwl=wils[match_tagplev(ivl,wils...)] #now find the W link index with the same tags/plev as ivl
    iwqx=noncommonind(wils,iwl) #get the other link l=n index on W
    off=V_offsets(ms)
    @mpoc_assert off.o1==off.o2
    # 
    # W & V need to have the same Link tags as W1 for the assignments below to work.
    #
    W=replacetags(W,tags(iwqx),tags(iqx))
    V=replacetags(V,tags(ivqx),tags(iqx)) #V needs to have the same Link tags as W for the assignment below to work.
    iwqx,=inds(W,tags=tags(iqx))
    #
    #  Make a new tensor to copy V and one row of W into
    #
    iss=filterinds(inds(W),tags="Site")
    T=eltype(V)
    W1=ITensor(T(0.0),iqx,iwl,iss)
    rc= off.o1==1 ? 1 : dim(iwqx) #preserve row/col 1 or Dw
    rc1= off.o1==1 ? 1 : dim(iqx)
    #@show iwqx rc iqx rc1 iwl
    #@pprint W
    #@show W[iwqx=>rc:rc,iwl=>1:dim(iwl)]
    W1[iqx=>rc1:rc1,iwl=>1:dim(iwl)]=W[iwqx=>rc:rc,iwl=>1:dim(iwl)] #copy row/col rc/rc1
    #@pprint W1
    if dim(iqx)==1
        W1[iqx=>1:1,range(iwl,off.o2)]=V 
    elseif dim(iwl)==1
        W1[range(iqx,off.o1),iwl=>1:1]=V
    else
        W1[range(iqx,off.o1),range(iwl,off.o2)]=V #Finally we can do the assingment of the V-block.
    end
    return W1
end

#
#  o1   add row to RL       o2  add column to RL
#   0   at bottom, Dw1+1    0   at right, Dw2+1
#   1   at top, 1           1   at left, 1
#
function growRL(RL::ITensor,iwl::Index,off::V_offsets,qn::Union{QN,Int})::Tuple{ITensor,Index}
    @mpoc_assert order(RL)==2
    @checkflux(RL)
    irl,=filterinds(inds(RL),tags=tags(iwl)) #find the link index of RL
    irqx=noncommonind(inds(RL),irl) #find the qx link of RL
    @mpoc_assert dim(iwl)==dim(irl)+1
    ipqx=redim(irqx,dim(irqx)+1,off.o1,qn) 
    T=eltype(RL)
    RLplus=ITensor(T(0.0),iwl,ipqx)
    RLplus[ipqx=>1,iwl=>1]=1.0 #add 1.0's in the corners
    RLplus[ipqx=>dim(ipqx),iwl=>dim(iwl)]=1.0
    RLplus[range(ipqx,off.o1),range(iwl,off.o2)]=RL #plop in RL in approtriate sub block.
    @checkflux(RL) 
    return RLplus,dag(ipqx)
end

#
#  factor LR such that for
#       lr=left  LR=M*RM_prime
#       lr=right LR=RL_prime*M
#  However becuase of how the ITensor index works we don't need to distinguish between left and 
#  right matrix multiplication in the code.  THis simplified code requires the RL is square.
#

function getM(RL::ITensor,ul::reg_form)::Tuple{ITensor,ITensor,Index}
    @mpoc_assert order(RL)==2
    @checkflux(RL)
    mtags=ts"Link,m"
    iqx,=inds(RL,tags="Link,qx") #Grab the qx link index
    il=noncommonind(RL,iqx) #Grab the remaining link index
    Dw=dim(iqx)
    @mpoc_assert Dw==dim(il) #make sure RL is square
    
    M=RL[iqx=>2:Dw-1,il=>2:Dw-1] #pull out the M sub block
    #
    # Now we need RL_prime such that RL=M*RL_prime.
    # RL_prime is just the perimeter of RL with 1's on the diagonal
    #
    RL=replacetags(RL,tags(iqx),mtags)  #change Link,qx to Link,m
    iqx=replacetags(iqx,tags(iqx),mtags)
    im=redim(iqx,Dw) #new common index between M_plus and RL_prime
    RL_prime=ITensor(0.0,im,il)
    #
    #  Copy over the perimeter of RL.
    #
    if ul==upper
        RL_prime[im=>1:1,il=>1:Dw]=RL[iqx=>1:1 ,il=>1:Dw] #first row
        RL_prime[im=>2:Dw,il=>Dw:Dw]=RL[iqx=>2:Dw,il=>Dw:Dw] #last col
    else
        RL_prime[im=>Dw:Dw,il=>2:Dw]=RL[iqx=>Dw:Dw,il=>2:Dw] #last row
        RL_prime[im=>1:Dw,il=>1:1]=RL[iqx=>1:Dw,il=>1:1] #first col
    end
    
    # Fill in interior diaginal
    for j1 in 2:Dw-1 #
        RL_prime[im=>j1,il=>j1]=1.0
    end
    @checkflux(RL_prime)
    M=replacetags(M,tags(il),mtags) #change Link,l=n to Link,m
   
    return M,RL_prime,dag(im)
end


function show_blocks(T::ITensor)
    for b in nzblocks(T)
        qns=ntuple(i->space(inds(T)[i])[b[i]],length(inds(T)))
        @show b,qns
    end
end

function my_similar(::DenseTensor{ElT,N},inds...) where {ElT,N}
    return ITensor(inds...)
end

function my_similar(::BlockSparseTensor{ElT,N},inds...) where {ElT,N}
    return ITensor(inds...)
end

function my_similar(::DiagTensor{ElT,N},inds...) where {ElT,N}
    return diagITensor(inds...)
end

function my_similar(::DiagBlockSparseTensor{ElT,N},inds...) where {ElT,N}
    return diagITensor(inds...)
end

function my_similar(T::ITensor,inds...)
    return my_similar(tensor(T),inds...)
end

function warn_space(A::ITensor,ig::Index)
    ia,=inds(A,tags=tags(ig),plev=plev(ig))
    @mpoc_assert dim(ia)+2==dim(ig)
    if hasqns(A)
        sa,sg=space(ia),space(ig)
        if dir(ia)!=dir(ig)
            sa=-sa
        end
        if sa!=sg[2:nblocks(ig)-1]
            @warn "Mismatched spaces:"
            @show sa sg[2:nblocks(ig)-1] dir(ia) dir(ig)
            #@assert false
        end
    end
end
#                      |1 0 0|
#  given A, spit out G=|0 A 0| , indices of G are provided.
#                      |0 0 1|
function grow(A::ITensor,ig1::Index,ig2::Index)
    @checkflux(A) 
    @mpoc_assert order(A)==2
    warn_space(A,ig1)
    warn_space(A,ig2)
    Dw1,Dw2=dim(ig1),dim(ig2)
    G=my_similar(A,ig1,ig2)
    G[ig1=>1  ,ig2=>1  ]=1.0;
    @checkflux(G) 
    G[ig1=>Dw1,ig2=>Dw2]=1.0;
    @checkflux(G) 
    G[ig1=>2:Dw1-1,ig2=>2:Dw2-1]=A
    @checkflux(G) 
    return G
end
