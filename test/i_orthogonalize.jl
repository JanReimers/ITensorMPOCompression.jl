using ITensors
#using NDTensors
using ITensorMPOCompression
using ITensorInfiniteMPS
using Printf
using Test

using Printf
Base.show(io::IO, f::Float64) = @printf(io, "%1.4f", f)

@testset "Orthogonalize InfiniteMPO 2-body Hamiltonians, ul=$ul, qbs=$qns" for ul in [lower,upper], qns in [false,true]
    initstate(n) = "↑"
    @printf "               Dw     Dw    Dw    Dw\n"
    @printf " Ncell  NNN  uncomp. left  right  LR\n"
    for N in [1,2,4], NNN in [2,4] #3 site unit cell fails for qns=true.
        si = infsiteinds("S=1/2", N; initstate, conserve_szparity=qns)

        H0=make_transIsing_iMPO(si,NNN;ul=ul,pbc=true)
        @test is_regular_form(H0)
        Dw0=Base.max(get_Dw(H0)...)

        HL=copy(H0)
        @test is_regular_form(HL)
        GL=ITensorMPOCompression.orthogonalize!(HL;orth=left)
        DwL=Base.max(get_Dw(HL)...)
        @test is_regular_form(HL)
        @test is_orthogonal(HL,left)
        for n in 1:N
            @test norm(HL[n]*GL[n]-GL[n-1]*H0[n]) ≈ 0.0 atol = 1e-14 
        end
        HR=copy(H0)
        GR=ITensorMPOCompression.orthogonalize!(HR;orth=right)
        DwR=Base.max(get_Dw(HR)...)
        @test is_regular_form(HR)
        @test is_orthogonal(HR,right)
        for n in 1:N
            @test norm(GR[n-1]*HR[n]-H0[n]*GR[n]) ≈ 0.0 atol = 1e-14
        end   
        HR1=copy(HL) 
        G=ITensorMPOCompression.orthogonalize!(HR1;orth=right)
        DwLR=Base.max(get_Dw(HR1)...)
        @test is_regular_form(HR1)
        @test is_orthogonal(HR1,right)
        for n in 1:N
            D1=G[n-1]*HR1[n]
            @assert order(D1)==4
            D2=HL[n]*G[n]
            @assert order(D2)==4
            @test norm(G[n-1]*HR1[n]-HL[n]*G[n]) ≈ 0.0 atol = 1e-14
        end   
        @printf " %4i %4i   %4i   %4i  %4i  %4i\n" N NNN Dw0 DwL DwR DwLR

    end
end

@testset "Truncate/Compress InfiniteMPO 2-body Hamiltonians, ul=$ul, qbs=$qns" for ul in [lower,upper], qns in [false,true]
    initstate(n) = "↑"
    @printf "               Dw     Dw    Dw   \n"
    @printf " Ncell  NNN  uncomp. left  right \n"

    for N in [1,2,4], NNN in [2,4] #3 site unit cell fails for qns=true.
        si = infsiteinds("S=1/2", N; initstate, conserve_szparity=qns)
        H0=make_transIsing_iMPO(si,NNN;ul=ul,pbc=true)
        @test is_regular_form(H0)
        Dw0=Base.max(get_Dw(H0)...)
        #
        #  Do truncate outputting left ortho Hamiltonian
        #
        HL=copy(H0)
        Ss,ss,HR=truncate!(HL;orth=left,cutoff=1e-15,h_mirror=true)
        DwL=Base.max(get_Dw(HL)...)
        # @show Ss ss 
        # @pprint(HL[1])
        @test is_regular_form(HL)
        @test is_orthogonal(HL,left)
        #
        #  Now test guage relations using the diagonal singular value matrices
        #  as the gauge transforms.
        #
        for n in 1:N
            @test norm(Ss[n-1]*HR[n]-HL[n]*Ss[n]) ≈ 0.0 atol = 1e-14
        end    
        #
        #  Do truncate from H0 outputting right ortho Hamiltonian
        #
        HR=copy(H0)
        Ss,ss,HL=truncate!(HR;orth=right,cutoff=1e-15,h_mirror=true)
        DwR=Base.max(get_Dw(HR)...)
        #@pprint(HR[1])
        @test is_regular_form(HR)
        @test is_orthogonal(HR,right)
        for n in 1:N
            #@show inds(Ss[n-1]) inds(HR[n],tags="Link") inds(HL[n],tags="Link") inds(Ss[n])
            @test norm(Ss[n-1]*HR[n]-HL[n]*Ss[n]) ≈ 0.0 atol = 1e-14
        end   
        @printf " %4i %4i   %4i   %4i  %4i \n" N NNN Dw0 DwL DwR

    end
end

@testset "Orthogonalize/truncate verify gauge invariace of <ψ|H|ψ>, ul=$ul, qbs=$qns" for ul in [lower,upper], qns in [false]
    initstate(n) = "↑"
    for N in [1], NNN in [2,4] #3 site unit cell fails for qns=true.
        si = infsiteinds("S=1/2", N; initstate, conserve_szparity=qns)
        ψ = InfMPS(si, initstate)
        for n in 1:N
            ψ[n] = randomITensor(inds(ψ[n]))
        end
        H0=make_transIsing_iMPO(si,NNN;ul=ul,pbc=true)
        Hsum0=InfiniteSum{MPO}(H0,NNN)
        E0=expect(ψ,Hsum0)

        HL=copy(H0)
        orthogonalize!(HL;orth=left)
        HsumL=InfiniteSum{MPO}(HL,NNN)
        EL=expect(ψ,HsumL)
        @test EL ≈ E0 atol = 1e-14

        HR=copy(HL)
        orthogonalize!(HR;orth=right)
        HsumR=InfiniteSum{MPO}(HR,NNN)
        ER=expect(ψ,HsumR)
        @test ER ≈ E0 atol = 1e-14

        HL=copy(H0)
        truncate!(HL;orth=left)
        HsumL=InfiniteSum{MPO}(HL,NNN)
        EL=expect(ψ,HsumL)
        @test EL ≈ E0 atol = 1e-14

        HR=copy(H0)
        truncate!(HR;orth=right)
        HsumR=InfiniteSum{MPO}(HR,NNN)
        ER=expect(ψ,HsumR)
        @test ER ≈ E0 atol = 1e-14
        truncate!(HR;orth=left)
        HsumR=InfiniteSum{MPO}(HR,NNN)
        ER=expect(ψ,HsumR)
        @test ER ≈ E0 atol = 1e-14

        #@show E0 EL ER E0-EL
        #@show get_Dw(H0) get_Dw(HL) get_Dw(HR)
    end
end




nothing

