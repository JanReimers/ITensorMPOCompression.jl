mutable struct reg_form_Op
    W::ITensor
    ileft::Index
    iright::Index
    ul::reg_form
    function reg_form_Op(W::ITensor, ileft::Index, iright::Index, ul::reg_form)
      if !hasinds(W, ileft, iright)
        @show inds(W, tags="Link") ileft iright
      end
      @assert hasinds(W, ileft, iright)
      return new(W, ileft, iright, ul)
    end
    function reg_form_Op(W::ITensor, ul::reg_form)
      return new(W, Index(1), Index(1), ul)
    end
  end
  
  function Base.getindex(Wrf::reg_form_Op, rleft::UnitRange, rright::UnitRange)
    return Wrf.W[Wrf.ileft => rleft, Wrf.iright => rright]
  end
  
  function detect_regular_form(Wrf::reg_form_Op, eps::Float64=default_eps)::Tuple{Bool,Bool}
    return is_regular_form(Wrf, lower, eps), is_regular_form(Wrf, upper, eps)
  end
  
  
  
  function is_regular_form(Wrf::reg_form_Op, eps::Float64=default_eps)
    return is_regular_form(Wrf, Wrf.ul, eps)
  end
  
  function is_regular_form(Wrf::reg_form_Op, ul::reg_form, eps::Float64=default_eps)::Bool
    ul_cache = Wrf.ul
    Wrf.ul = flip(ul)
    Wb = extract_blocks(Wrf, left; b=true, c=true, d=true)
    is = siteinds(Wrf)
    𝕀 = delta(is) #We need to make our own, can't trust Wb.𝕀 is ul is wrong.
    dh = dim(is[1])
    nr, nc = dims(Wrf)
    if (nc == 1 && ul == lower) || (nr == 1 && ul == upper)
      i1 = abs(scalar(dag(𝕀) * slice(Wrf.W, Wrf.ileft => 1, Wrf.iright => 1)) - dh) < eps
      iN = bz = cz = dz = true
    end
    if (nr == 1 && ul == lower) || (nc == 1 && ul == upper)
      iN = abs(scalar(dag(𝕀) * slice(Wrf.W, Wrf.ileft => nr, Wrf.iright => nc)) - dh) < eps
      i1 = bz = cz = dz = true
    end
    if nr > 1 && nc > 1
      i1 = abs(scalar(dag(Wb.𝕀) * slice(Wrf.W, Wrf.ileft => 1, Wrf.iright => 1)) - dh) < eps
      iN = abs(scalar(dag(Wb.𝕀) * slice(Wrf.W, Wrf.ileft => nr, Wrf.iright => nc)) - dh) < eps
      bz = isnothing(Wb.𝐛̂) ? true : norm(Wb.𝐛̂) < eps
      cz = isnothing(Wb.𝐜̂) ? true : norm(Wb.𝐜̂) < eps
      dz = norm(Wb.𝐝̂) < eps
    end
  
    Wrf.ul = ul_cache
    # if !(i1 && iN && bz && cz && dz)
    #     pprint(Wrf.W)
    #     @show ul nr nc i1 iN bz cz dz
    #     @show dh scalar(dag(𝕀) * slice(Wrf.W,Wrf.ileft=>1,Wrf.iright=>1)) Wb.𝕀 𝕀
    # end
  
    return i1 && iN && bz && cz && dz
  end
  
  function Base.show(io::IO, Wrf::reg_form_Op)
    show(io, Wrf.ileft)
    show(io, Wrf.iright)
    return show(io, Wrf.W)
  end
  
  
  ITensors.order(Wrf::reg_form_Op) = order(Wrf.W)
  
  function check_ortho(Wrf::reg_form_Op, lr::orth_type, eps::Float64=default_eps)::Bool
    Wb = extract_blocks(Wrf, lr; V=true)
    DwDw = dim(Wb.irV) * dim(Wb.icV)
    ilf = llur(Wrf, lr) ? Wb.icV : Wb.irV
  
    Id = Wb.𝐕̂ * prime(dag(Wb.𝐕̂), ilf) / d(Wb)
    if order(Id) == 2
      is_can = norm(dense(Id) - delta(ilf, dag(ilf'))) / sqrt(DwDw) < eps
      # if !is_can
      #     @show Id
      # end
    elseif order(Id) == 0
      is_can = abs(scalar(Id) - d(Wb)) < eps
    end
    return is_can
  end
  
  ITensors.dims(Wrf::reg_form_Op) = dim(Wrf.ileft), dim(Wrf.iright)
  Base.getindex(Wrf::reg_form_Op, lr::orth_type) = lr == left ? Wrf.ileft : Wrf.iright
  function Base.setindex!(Wrf::reg_form_Op, il::Index, lr::orth_type)
    if lr == left
      Wrf.ileft = il
    else
      Wrf.iright = il
    end
  end
  
  
  ITensors.inds(Wrf::reg_form_Op;kwargs...) = inds(Wrf.W;kwargs...)
  
  function ITensors.setinds(Wrf::reg_form_Op, is)::reg_form_Op
    ITensors.setinds(Wrf.W, is)
    Wrf.ileft, Wrf.iright = parse_links(Wrf.W, left)
    return Wrf
  end
  
  forward(Wrf::reg_form_Op, lr::orth_type) = Wrf[mirror(lr)]
  backward(Wrf::reg_form_Op, lr::orth_type) = Wrf[lr]
  
  ITensors.siteinds(Wrf::reg_form_Op) = noncommoninds(Wrf.W, Wrf.ileft, Wrf.iright)
  ITensors.linkinds(Wrf::reg_form_Op) = Wrf.ileft, Wrf.iright
  ITensors.linkinds(Wrf::reg_form_Op, lr::orth_type) = backward(Wrf, lr), forward(Wrf, lr)
  
  function check(Wrf::reg_form_Op)
    @mpoc_assert order(Wrf.W) == 4
    @mpoc_assert tags(Wrf.ileft) != tags(Wrf.iright) || plev(Wrf.ileft) != plev(Wrf.iright)
    @mpoc_assert hasinds(Wrf.W, Wrf.ileft)
    @mpoc_assert hasinds(Wrf.W, Wrf.iright)
    if hasqns(Wrf.W)
      @mpoc_assert dir(Wrf.W, Wrf.ileft) == dir(Wrf.ileft)
      @mpoc_assert dir(Wrf.W, Wrf.iright) == dir(Wrf.iright)
    end
  end
  
  #
  # Detect which link index ileft/iright is common with B
  # and replace it with the correct remaining link from B
  #
  function product(Wrf::reg_form_Op, B::ITensor)::reg_form_Op
    WB = Wrf.W * B
    ic = commonind(Wrf.W, B)
    @assert hastags(ic, "Link")
    new_index = noncommonind(B, ic, siteinds(Wrf))
    if ic == Wrf.iright
      return reg_form_Op(WB, Wrf.ileft, new_index, Wrf.ul)
    elseif ic == Wrf.ileft
      return reg_form_Op(WB, new_index, Wrf.iright, Wrf.ul)
    else
      @assert false
    end
  end
  
  Base.:*(Wrf::reg_form_Op, B::ITensor)::reg_form_Op = product(Wrf, B)
  Base.:*(A::ITensor, Wrf::reg_form_Op)::reg_form_Op = product(Wrf, A)
  
  function ITensors.replacetags(Wrf::reg_form_Op, tsold, tsnew)
    Wrf.W = replacetags(Wrf.W, tsold, tsnew)
    Wrf.ileft = replacetags(Wrf.ileft, tsold, tsnew)
    Wrf.iright = replacetags(Wrf.iright, tsold, tsnew)
    return Wrf
  end
  
  function ITensors.replaceind(Wrf::reg_form_Op, iold::Index, inew::Index)
    W= replaceind(Wrf.W, iold, inew)
    if Wrf.ileft==iold
      ileft=inew
      iright=Wrf.iright
    elseif Wrf.iright==iold
      ileft=Wrf.ileft
      iright=inew
    else
      @assert false
    end
    return reg_form_Op(W,ileft,iright,Wrf.ul)
  end
  
  
  