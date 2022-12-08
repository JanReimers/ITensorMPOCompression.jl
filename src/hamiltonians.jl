
#make_Heisenberg_AutoMPO
make_Heisenberg_AutoMPO(sites,NNN::Int64,hz::Float64,::reg_form,J::Float64=1.0)::MPO = make_Heisenberg_AutoMPO(sites,NNN,hz,J)
    
# make_Heisenberg_AutoMPO(sites,NNN::Int64,hz::Float64,ul::reg_form)::MPO = 
#     make_Heisenberg_AutoMPO(sites,NNN,hz,1.0)

@doc """
    make_Heisenberg_AutoMPO(sites,[NNN=1[,hz=0.0[,J=1.0]]])

Use `ITensor.autoMPO` to build up a Heisenberg model Hamiltonian with up to `NNN` neighbour
interactions.  The interactions are hard coded to decay like J/(i-j) between sites `i` and `j`.
The MPO is returned in lower regular form.
    
# Arguments
- `sites` : Site set defining the lattice of sites.
- `NNN::Int64` : Number of nearest neighbour interactions to include in `H`
- `hz::Float64=0.0` : External magnetic field in `z` direction.
- `J::Float64=1.0` : Nearest neighbour interaction strength.

"""
function make_Heisenberg_AutoMPO(sites,NNN::Int64=1,hz::Float64=0.0,J::Float64=1.0)::MPO
    N=length(sites)
    @assert(N>=NNN)
    ampo = OpSum()
    for j=1:N
        add!(ampo, hz   ,"Sz", j)
    end
    for dj=1:NNN
        f=J/dj
        for j=1:N-dj
            add!(ampo, f    ,"Sz", j, "Sz", j+dj)
            add!(ampo, f*0.5,"S+", j, "S-", j+dj)
            add!(ampo, f*0.5,"S-", j, "S+", j+dj)
        end
    end
    return MPO(ampo,sites)
end

#
#  Reproduce the 3-body Hamiltonian from the Parker paper, eq. 34
#
function make_Parker(sites,hx::Float64=0.0;kwargs...)
    N=length(sites)
    os = OpSum()
    if hx!=0
        os=make_1body(os,N,hx)
    end
    os=make_2body(os,N)
    os=make_3body(os,N)
    MPO(os,sites;kwargs...)
end

function make_1body(os::OpSum,N::Int64,hx::Float64=0.0)::OpSum
    for n=1:N
        add!(os, hx   ,"Sx", n)
    end
    return os
end

function make_2body(os::OpSum,N::Int64,heis::Bool=false)::OpSum
    for n=1:N
        for m=n+1:N
            Jnm=1.0/abs(n-m)^4
            add!(os, Jnm    ,"Sz", n, "Sz", m)
            if heis
                add!(os, Jnm*0.5,"S+", n, "S-", m)
                add!(os, Jnm*0.5,"S-", n, "S+", m)
            end
        end
    end
    return os
end

function make_3body(os::OpSum,N::Int64)::OpSum
    for n=1:N
        for m=n+1:N
            Jnm=1.0/abs(n-m)^2
            for k=m+1:N
                Jkn=1.0/abs(k-n)^2
                add!(os, Jnm*Jkn    ,"Sz", n, "Sz", m,"Sz",k)
            end
        end
    end
    return os
end




make_transIsing_AutoMPO(sites,NNN::Int64,hx::Float64,ul::reg_form,J::Float64=1.0)::MPO = 
     make_transIsing_AutoMPO(sites,NNN,hx,J)

@doc """
    make\\_transIsing\\_AutoMPO(sites,NNN[,hx=0.0[,J=1.0]])
 
 Use `ITensor.autoMPO` to build up a transverse Ising model Hamiltonian with up to `NNN` neighbour
 interactions.  The interactions are hard coded to decay like J/(i-j) between sites `i` and `j`.
 The MPO is returned in lower regular form.
     
 # Arguments
 - `sites` : Site set defining the lattice of sites.
 - `NNN::Int64` : Number of nearest neighbour interactions to include in `H`
 - `hx::Float64=0.0` : External magnetic field in `x` direction.
 - `J::Float64=1.0` : Nearest neighbour interaction strength.
 
 """
function make_transIsing_AutoMPO(sites,NNN::Int64=1,hx::Float64=0.0,J::Float64=1.0)::MPO
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
    return MPO(ampo,sites)
end


@doc """
    make_transIsing_MPO(sites[,NNN=1[,hx=0.0[,ul=lower[,J=1.0]]]])
 
Directly coded build up of a transverse Ising model Hamiltonian with up to `NNN` neighbour
interactions.  The interactions are hard coded to decay like J/(i-j) between sites `i` and `j`.
     
# Arguments
- `sites` : Site set defining the lattice of sites.
- `NNN::Int64=1` : Number of nearest neighbour interactions to include in `H`
- `hx::Float64=0.0` : External magnetic field in `x` direction.
- `ul::reg_form=lower` : build H with `lower` or `upper` regular form.
- `J::Float64=1.0` : Nearest neighbour interaction strength.

"""
function make_transIsing_MPO(sites,NNN::Int64=1,hx::Float64=0.0,ul::reg_form=lower,J::Float64=1.0;kwargs...)::MPO
    pbc::Bool=get(kwargs,:pbc,false)
    Dw::Int64=transIsing_Dw(NNN)
    use_qn::Bool=hasqns(sites)
    mpo=MPO(length(sites))
    io = ul==lower ? ITensors.Out : ITensors.In
    prev_link=make_Ising_index(Dw,"Link,l=0",use_qn,io)
    for n in 1:length(sites)
        mpo[n]=make_transIsing_op(sites[n],prev_link,NNN,J,hx,ul)
        prev_link=filterinds(mpo[n],tags="Link,l=$n")[1]
    end
    if !pbc
        mpo=ITensorMPOCompression.to_openbc(mpo) #contract with l* and *r at the edges.
    end
    return mpo
end

#  It turns out that the trans-Ising model
#  Dw = 2+Sum(i,i=1..NNN) =2 + NNN*(NNN+1)/2
#
function transIsing_Dw(NNN::Int64)::Int64
    return 2+NNN*(NNN+1)/2
end

function make_Ising_index(Dw::Int64,tags::String,use_qn::Bool,dir)
    if (use_qn)
        if tags[1:4]=="Link"
            ind=Index(QN("Sz",0)=>Dw;dir=dir,tags=tags)
        else
            @assert tags[1:4]=="Site"
            ind=Index(QN("Sz",1)=>Dw;dir=dir,tags=tags)
        end
    else
        ind=Index(Dw,tags)
    end
    return ind
end

# NNN = Number of Nearest Neighbours, for example
#    NNN=1 corresponds to nearest neighbour
#    NNN=2 corresponds to nearest and next nearest neighbour
function make_transIsing_op(site::Index,prev_link::Index,NNN::Int64,J::Float64,hx::Float64=0.0,ul::reg_form=lower)::ITensor
    @assert NNN>=1
    do_field = hx!=0.0
    Dw::Int64=transIsing_Dw(NNN)
    nl=parse_link(prev_link)
    n,space=parse_site(site)
    @assert n==nl+1
    use_qn=hasqns(site)
    
    r=dag(prev_link)
    c=make_Ising_index(Dw,"Link,l=$n",use_qn,dir(prev_link))
    is=dag(site) #site seem to have the wrong direction!
    W=ITensor(r,c,is,dag(is'))
    Id=op(is,"Id")
    Sz=op(is,"Sz")
    if do_field
        Sx=op(is,"Sx")
    end
    assign!(W,Id,r=>1 ,c=>1 )
    assign!(W,Id,r=>Dw,c=>Dw)

    iblock=1
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
