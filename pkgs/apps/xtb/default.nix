{ stdenv
, lib
, gfortran
, fetchFromGitHub
, fetchpatch
, cmake
, makeWrapper
, blas
, lapack
, writeTextFile
, mctc-lib
, test-drive
, tblite
, toml-f
, simple-dftd3
, dftd4
, multicharge
, enableTurbomole ? false
, turbomole
, enableOrca ? false
, orca
, cefine
}:

assert !blas.isILP64 && !lapack.isILP64;

let
  description = "Semiempirical extended tight-binding program package";

  binSearchPath = lib.strings.makeSearchPath "bin" ([ ]
    ++ lib.optional enableTurbomole turbomole
    ++ lib.optional enableOrca orca
    ++ lib.optional enableTurbomole cefine
  );

in
stdenv.mkDerivation rec {
  pname = "xtb";
  version = "6.6.1";

  src = fetchFromGitHub {
    owner = "grimme-lab";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-I2K87W/b/Nh2VCkINhmCwe4HwBZ7ZIYM5cUYc/8Hkws=";
  };

  nativeBuildInputs = [
    gfortran
    cmake
    makeWrapper
  ];

  buildInputs = [
    blas
    lapack
    mctc-lib
    tblite
    test-drive
    toml-f
    simple-dftd3
    dftd4
    multicharge
  ];

  hardeningDisable = [ "format" ];

  postInstall = ''
    mkdir -p $out/lib/pkgconfig

    cat > $out/lib/pkgconfig/xtb.pc << EOF
    prefix=$out
    libdir=''${prefix}/lib
    includedir=''${prefix}/include

    Name: ${pname}
    Description: ${description}
    Version: ${version}
    Cflags: -I''${prefix}/include
    Libs: -L''${prefix}/lib -lxtb
    EOF
  '';

  postFixup = ''
    wrapProgram $out/bin/xtb \
      --prefix PATH : "${binSearchPath}" \
      --set-default XTBPATH $out/share/xtb
  '';

  doCheck = true;
  preCheck = ''
    export OMP_NUM_THREADS=2
  '';

  passthru = { inherit enableOrca enableTurbomole; };

  meta = with lib; {
    inherit description;
    homepage = "https://github.com/grimme-lab/xtb";
    license = licenses.lgpl3Only;
    platforms = platforms.linux;
    maintainers = [ maintainers.sheepforce ];
  };
}
