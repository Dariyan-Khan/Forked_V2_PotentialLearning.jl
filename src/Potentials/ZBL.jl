"""
    Ziegler-Biersack-Littmark (ZBL) Potential
    
See https://docs.lammps.org/pair_zbl.html
"""
mutable struct ZBL <: Potential
    ε0::Float64      # Electrical permittivity of vacuum.
    e::Float64       # Electron charge.
    zi::Float64      # Atomic number of the atom i.
    zj::Float64      # Atomic number of the atom j.
    a::Float64
    r_inner::Float64 # Inner cutoff. Distance where switching function begins.
    r_outer::Float64 # Outer cutoff. Global cutoff for ZBL interaction.
    A::Float64
    B::Float64
    C::Float64
end

# TODO: check this function: "exp" or "e"
function ϕ(p::ZBL, x::Float64)
    return   0.18175 * exp(-3.1998*x)  + 0.50986 * exp(-0.94229*x) +
             0.28022 * exp(-0.40290*x) + 0.2817  * exp(-0.20162*x)
end

function zbl(p::ZBL, r::Float64)
    return 1 / (4.0 * π * p.ε0) * p.zi * p.zj * p.e^2 / r * ϕ(p, r / p.a)
end

function zbl′(p, r)
    return gradient(r -> zbl(p, r), r)[1]
end

function zbl′′(p, r)
    return gradient(r -> zbl′(p, r), r)[1]
end

function ZBL(params::Dict)

    # Read parameters from a configuration file
    ZBL_params = load_params(string(params["path"], "/ZBL.conf"))

    # Creates the ZBL model
    ε0 = ZBL_params["ε0"]
    e = ZBL_params["e"]
    zi = ZBL_params["zi"]
    zj = ZBL_params["zj"]
    a = 0.46850 / (zi^0.23 + zj^0.23)
    r_inner = ZBL_params["r_inner"]
    r_outer = ZBL_params["r_outer"]
    
    p = ZBL(ε0, e, zi, zj, a, r_inner, r_outer, 0.0, 0.0, 0.0)
    
    # See https://docs.lammps.org/pair_zbl.html
    #     https://docs.lammps.org/pair_gromacs.html
    #
    #   E(r_outer) = zbl(p, r_outer) + S(r_outer)
    #   S(r_outer) = -E(r_outer)
    #   S′(r_outer) = -E′(r_outer)
    #   S′′(r_outer) = -E′′(r_outer)
    #   =>
    E(r) = -zbl(p, r) / 2.0
    E′(r) = -zbl′(p, r) / 2.0
    E′′(r) = -zbl′′(p, r) / 2.0
    
    p.A = (-3.0 * E′(r_outer) + (r_outer - r_inner) * E′′(r_outer)) / (r_outer - r_inner)^2
    p.B = (-2.0 * E′(r_outer) - (r_outer - r_inner) * E′′(r_outer)) / (r_outer - r_inner)^3
    p.C = -E(r_outer) + 0.5 * (r_outer - r_inner) * E′(r_outer)
          -1.0 / 12.0 * (r_outer - r_inner)^2 * E′′(r_outer)

    return p
end



"""
    S(r)

Switching function that ramps the energy, force, and curvature smoothly to zero
between an inner and outer cutoff. Here, the inner and outer cutoff are the same
for all pairs of atom types.
"""
function S(p::ZBL, r::Float64)
    if r < p.r_inner
        return p.C
    elseif p.r_inner < r && r < p.r_outer
        return p.A / 3.0 * (r - p.r_inner)^3 + p.B / 4.0 * (r - p.r_inner)^4 + p.C
    else
        return 0.0 # TODO: check this
    end
end

function potential_energy(p::ZBL, r::Position, args...)
    return  zbl(p, norm(r)) + S(p, norm(r))
end
