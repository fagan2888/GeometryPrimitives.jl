export Ellipsoid

mutable struct Ellipsoid{N,N²,D} <: Shape{N,N²,D}
    c::SVector{N,Float64}  # center of ellipsoid
    ri2::SVector{N,Float64}  # inverse squares of "radii" (semi-axes) in axis directions
    p::SMatrix{N,N,Float64,N²}  # projection matrix to Ellipsoid coordinates; must be orthonormal (see surfpt_nearby)
    data::D  # auxiliary data
    Ellipsoid{N,N²,D}(c,ri2,p,data) where {N,N²,D} = new(c,ri2,p,data)  # suppress default outer constructor
end

Ellipsoid(c::SVector{N,<:Real},
          r::SVector{N,<:Real},
          axes::SMatrix{N,N,<:Real}=SMatrix{N,N,Float64}(I),
          data::D=nothing) where {N,D} =
    Ellipsoid{N,N*N,D}(c, float.(r).^-2, inv(axes ./ sqrt.(sum(abs2,axes,dims=Val(1)))), data)

Ellipsoid(c::AbstractVector{<:Real},  # center of ellipsoid
          r::AbstractVector{<:Real},  # ""
          axes::AbstractMatrix{<:Real}=Matrix{Float64}(I,length(c),length(c)),  # columns are axes vector; assumed orthogonal
          data=nothing) =
    (N = length(c); Ellipsoid(SVector{N}(c), SVector{N}(r), SMatrix{N,N}(axes), data))

Ellipsoid(b::Box{N,N²,D}, data::D=nothing) where {N,N²,D} = Ellipsoid{N,N²,D}(b.c, (b.r).^-2, b.p, data)

Base.:(==)(b1::Ellipsoid, b2::Ellipsoid) = b1.c==b2.c && b1.ri2==b2.ri2 && b1.p==b2.p && b1.data==b2.data
Base.isapprox(b1::Ellipsoid, b2::Ellipsoid) = b1.c≈b2.c && b1.ri2≈b2.ri2 && b1.p≈b2.p && b1.data==b2.data
Base.hash(b::Ellipsoid, h::UInt) = hash(b.c, hash(b.ri2, hash(b.p, hash(b.data, hash(:Ellipsoid, h)))))

Base.in(x::SVector{N,<:Real}, b::Ellipsoid{N}) where {N} = dot((b.p * (x - b.c)).^2, b.ri2) ≤ 1.0

function surfpt_nearby(x::SVector{N,<:Real}, b::Ellipsoid{N}) where {N}
    if x == b.c
        _m, i = findmax(b.ri2)
        nout = b.p[i,:]  # assume b.p is orthogonal
        return b.c + nout/√b.ri2[i], nout
    end

    # For a given point x and equation of ellipsoid f(x) = 1, find t such that x₀ = x + t*∇f(x)
    # is on the ellipsoid.  Eventually this reduces to a quadratic equation for t.  The
    # following is evaluation of the quadratic formula in a numerically stable way.
    px = b.p * (x - b.c)  # in ellipsoid's coordinates
    px2 = px.^2

    px²r⁻² = px2 ⋅ b.ri2
    px²r⁻⁴ = px2 ⋅ (b.ri2.^2)
    px²r⁻⁶ = px2 ⋅ (b.ri2.^3)

    q24 = (px²r⁻² - 1) / px²r⁻⁴
    q64 = px²r⁻⁶ / px²r⁻⁴

    t = -q24 / (1 + √(1 - q24 * q64))

    # From t, recover x₀ = x + t*∇f(x).
    px₀ = (t*b.ri2 + 1) .* px  # surface point in ellipsoid coordinates

    # Transform back to the original coordinates.
    x₀ = b.p' * px₀ + b.c
    nout = normalize(b.p' * (px .* b.ri2))

    return x₀, nout
end

translate(b::Ellipsoid{N,N²,D}, ∆::SVector{N,<:Real}) where {N,N²,D} = Ellipsoid{N,N²,D}(b.c+∆, b.ri2, b.p, b.data)

function boundpts(b::Ellipsoid{N}) where {N}
    # Return the points tangential to the bounding box.
    # For N = 3, it returns three points at which the direction normals are +x, +y, +z
    # directions, respectively.

    r2 = 1 ./ b.ri2
    ndir = b.p  # Cartesian directions in ellipsoid coordinates: b.p * I

    # In the ellipsoid coordinates, the point on the ellipsoid where the direction normal is
    # n is (n .* r2) / sqrt(r2' * n.^2).  Below is the broadcasted version of this over a
    # matrix n, whose each column is a direction normal.  Once calculated, we need to
    # change the coordinates back to the original coordinates.
    M = b.p' * ((ndir .* r2) ./ sqrt.(r2' * ndir.^2))

    return M
end

function bounds(b::Ellipsoid{N}) where {N}
    M = boundpts(b)

    # Note that when M does not include NaN, we can simply set m = diag(M), because the
    # first (second, third) column of M is the point on the ellipsoid at which the normal
    # vector is +x (+y, +z).  Therefore, the x (y, z) point of the first (second, third)
    # column has the largest x (y, z) coordinate.
    #
    # However, if one of a, b, c is zero, the shape is a disk.  Then one column of M can be
    # completely filled with NaN.  This column must not be counted as a bounding point, so
    # we apply NaN-ignoring maximum by StaticArrays.reducedim along the row direction.
    #
    # For the efficient implementation of NaN-ignoring maximum, see
    # https://discourse.julialang.org/t/inconsistency-between-findmax-and-maximum-with-respect-to-nan/4214/8
    m = reduce((x,y) -> x<y ? y : x, M, init=-Inf, dims=Val(2))[:,1]

    return (b.c-m,b.c+m)
end
