
#handle case with 1 link index at edges.
function fix_autoMPO1(W::ITensor)::ITensor
    ils=filterinds(W,"Link")
    iss=filterinds(W,"Site")
    @assert length(ils)==1
    @assert length(iss)==2
    il=ils[1] #link index
    Dw=dim(il)
    p=collect(1:Dw)
    p[2],p[Dw]=p[Dw],p[2]
    W1=ITensor(il,iss...)
    for js in eachindval(iss)
        for jl in eachindval(il)
            Sl=slice(W,jl)
            assign!(W1,Sl,il=>p[jl.second])
        end
    end
    return W1
end

function fix_autoMPO(W::ITensor)::ITensor
    ils=filterinds(W,"Link")
    if length(ils)==1
        return fix_autoMPO1(W)
    end
    iss=filterinds(W,"Site")
    @assert length(ils)==2
    @assert length(iss)==2
    d,n,r,c=parse_links(W)
    Dw1,Dw2=dim(r),dim(c)
    #
    #  set up perm arrays to swap row and col 2 with N
    #
    pr=collect(1:Dw1)
    pc=collect(1:Dw2)
    pr[2],pr[Dw1]=pr[Dw1],pr[2]
    pc[2],pc[Dw2]=pc[Dw2],pc[2]
    W1=ITensor(r,c,iss...)
    for jr in eachindval(r)
        for jc in eachindval(c)
            sl=slice(W,jr,jc)
            assign!(W1,sl,r=>pr[jr.second],c=>pc[jc.second])
        end
    end
    return W1
end


function fix_autoMPO!(H::MPO)
    N=length(H)
    for n in 1:N
        H[n]=fix_autoMPO(H[n])
    end
end

make_Heisenberg_AutoMPO(sites,NNN::Int64,hx::Float64,ul::reg_form,J::Float64=1.0)::MPO = 
    make_Heisenberg_AutoMPO(sites,NNN,hx,J)

function make_Heisenberg_AutoMPO(sites,NNN::Int64,hx::Float64,J::Float64)::MPO
    N=length(sites)
    @assert(N>NNN)
    ampo = OpSum()
    for j=1:N
        add!(ampo, hx   ,"Sz", j)
    end
    for dj=1:NNN
        f=J/dj
        for j=1:N-dj
            add!(ampo, f    ,"Sz", j, "Sz", j+dj)
            add!(ampo, f*0.5,"S+", j, "S-", j+dj)
            add!(ampo, f*0.5,"S-", j, "S+", j+dj)
        end
    end
    mpo=MPO(ampo,sites)
    fix_autoMPO!(mpo) #swap row[2]<->row[Dw] and col[2]<->col[Dw]
    return mpo
end



make_transIsing_AutoMPO(sites,NNN::Int64,hx::Float64,ul::reg_form,J::Float64=1.0)::MPO = 
     make_transIsing_AutoMPO(sites,NNN,hx,J)

function make_transIsing_AutoMPO(sites,NNN::Int64,hx::Float64,J::Float64)::MPO
    do_field = hx!=0.0
    N=length(sites)
    @assert(N>NNN)
    ampo = OpSum()
    if do_field
        for j=1:N
            add!(ampo, hx   ,"Sx", j)
        end
    end
    for dj=1:NNN
        f=J/dj
        for j=1:N-dj
            add!(ampo, f    ,"Sz", j, "Sz", j+dj)
        end
    end
    mpo=MPO(ampo,sites)
    fix_autoMPO!(mpo) #swap row[2]<->row[Dw] and col[2]<->col[Dw]
    return mpo
end


function make_transIsing_MPO(sites,NNN::Int64=1,hx::Float64=0.0,ul::reg_form=lower,J::Float64=1.0)::MPO
    mpo=MPO(sites) #make and MPO only to get the indices
    prev_link=Nothing
    for n in 1:length(sites)
        mpo[n]=make_transIsing_op(mpo[n],prev_link,NNN,J,hx,ul)
        prev_link=filterinds(mpo[n],tags="Link,l=$n")[1]
    end
    return ITensorMPOCompression.to_openbc(mpo) #contract with l* and *r at the edges.
end

#  It turns out that the trans-Ising model
#  Dw = 2+Sum(i,i=1..NNN) =2 + NNN*(NNN+1)/2
#
function transIsing_Dw(NNN::Int64)::Int64
    return 2+NNN*(NNN+1)/2
end

function make_Ising_index(Dw::Int64,tags::String,use_qn::Bool,dir)
    if (use_qn)
        ind=Index(QN("Sz",0)=>Dw;dir=dir,tags=tags)
    else
        ind=Index(Dw,tags)
    end
    return ind
end

# NNN = Number of Nearest Neighbours, for example
#    NNN=1 corresponds to nearest neighbour
#    NNN=2 corresponds to nearest and next nearest neighbour
function make_transIsing_op(Wref::ITensor,prev_link,NNN::Int64,J::Float64,hx::Float64=0.0,ul::reg_form=lower)::ITensor
    @assert NNN>=1
    do_field = hx!=0.0
    Dw::Int64=transIsing_Dw(NNN)
    is=filterinds(Wref,tags="Site")[1] #get any site index for generating operators
    use_qn=hasqns(is)
    d,n,r,c=parse_links(Wref)
    if tags(r)==TagSet("")
        r=make_Ising_index(Dw,"Link,l=$(n-1)",use_qn,ITensors.In)
    else
        r=prev_link
    end
    if tags(c)==TagSet("")
        c=make_Ising_index(Dw,"Link,l=$n",use_qn,ITensors.Out)
    else
        c=redim(c,Dw)
    end
    iblock=1;
   
    W=ITensor(r,dag(c),is,dag(is'))
    Id=op(is,"Id")
    Sz=op(is,"Sz")
    if do_field
        Sx=op(is,"Sx")
    end
    assign!(W,Id,r=>1 ,c=>1 )
    assign!(W,Id,r=>Dw,c=>Dw)
    
    if ul==lower
        if do_field
            assign!(W ,hx*Sx,r=>Dw,c=>1); #add field term
        end
        #very hard to explain this without a diagram.
        for iNN in 1:NNN
            assign!(W,Sz,r=>iblock+1,c=>1)
            for jNN in 1:iNN-1
                assign!(W,Id,r=>iblock+1+jNN,c=>iblock+jNN)
            end
            Jn=J/(iNN) #interactions need to decay with distance in order for H to extensive 
            assign!(W,Jn*Sz,r=>Dw,c=>iblock+iNN)
            iblock+=iNN
        end
    else
        if do_field
            assign!(W,hx*Sx,r=>1,c=>Dw ); #add field term
        end
        #very hard to explain this without a diagram.
        for iNN in 1:NNN
            assign!(W,Sz,r=>1,c=>iblock+1)
            for jNN in 1:iNN-1
                assign!(W,Id,r=>iblock+jNN,c=>iblock+1+jNN)
            end
            Jn=J/(iNN) #interactions need to decay with distance in order for H to extensive 
            assign!(W,Jn*Sz,r=>iblock+iNN,c=>Dw)
            iblock+=iNN
        end
    end
    return W
end

function to_openbc(mpo::MPO)::MPO
    N=length(mpo)
    l,r=get_lr(mpo)    
    mpo[1]=l*mpo[1]
    mpo[N]=mpo[N]*r
    @assert length(filterinds(inds(mpo[1]),tags="Link"))==1
    @assert length(filterinds(inds(mpo[N]),tags="Link"))==1
    return mpo
end

function get_lr(mpo::MPO)::Tuple{ITensor,ITensor}
    ul::reg_form = is_lower_regular_form(mpo,1e-14) ? lower : upper
 
    N=length(mpo)
    W1=mpo[1]
    llink=filterinds(inds(W1),tags="l=0")[1]
    l=ITensor(0.0,dag(llink))

    WN=mpo[N]
    rlink=filterinds(inds(WN),tags="l=$N")[1]
    r=ITensor(0.0,dag(rlink))
    if ul==lower
        l[llink=>dim(llink)]=1.0
        r[rlink=>1]=1.0
    else
        l[llink=>1]=1.0
        r[rlink=>dim(rlink)]=1.0
    end

    return l,r
end


function fast_GS(H::MPO,sites)::Tuple{Float64,MPS}
    psi0  = randomMPS(sites,length(H))
    sweeps = Sweeps(5)
    setmaxdim!(sweeps, 2,4,8,16,32)
    setcutoff!(sweeps, 1E-10)
    E,psi= dmrg(H,psi0, sweeps;outputlevel=0)
    return E,psi
end
