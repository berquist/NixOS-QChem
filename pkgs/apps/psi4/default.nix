{ lib
, stdenv
, buildPythonPackage
, buildPackages
, makeWrapper
, fetchFromGitHub
, fetchFromGitLab
, fetchurl
, pkg-config
, writeTextFile
, cmake
, perl
, gfortran
, python
, pybind11
, qcelemental
, qcengine
, numpy
, pylibefp
, deepdiff
, blas
, lapack
, gau2grid
, libxc
, dkh
, dftd3
, pcmsolver
, libefp
, libecpint
, cppe
, chemps2
, hdf5
, hdf5-cpp
, mpfr
, gmpxx
, eigen
, boost
, adcc
, optking
, pytest
, mrcc
, enableMrcc ? false
, cfour
, enableCfour ? false
}:

let
  # Psi4 requires some special cmake flags. Using Nix's defaults usually does not work.
  specialInstallCmakeFlags = [
    "-DCMAKE_INSTALL_PREFIX=$out"
    "-DNAMESPACE_INSTALL_INCLUDEDIR=/"
    "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF"
    "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF"
    "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON"
    "-DCMAKE_SKIP_BUILD_RPATH=ON"
  ];

  chemps2_ = chemps2.overrideAttrs (oldAttrs: rec {
    configurePhase = ''
      cmake -Bbuild ${toString specialInstallCmakeFlags}
      cd build
    '';

    postFixup = ''
      substituteInPlace $out/share/cmake/CheMPS2/CheMPS2Config.cmake \
        --replace "1.14.1-2" "1.14.1"
    '';
  });

  dkh_ = dkh.overrideAttrs (oldAttrs: rec {
    enableParallelBuilding = true;
    configurePhase = "cmake -Bbuild ${toString (oldAttrs.cmakeFlags ++ specialInstallCmakeFlags)}";
    preBuild = "cd build";
  });

  pcmsolver_ = pcmsolver.overrideAttrs (oldAttrs: rec {
    enableParallelBuilding = true;
    configurePhase = ''
      cmake -Bbuild ${toString (oldAttrs.cmakeFlags ++ specialInstallCmakeFlags)}
      cd build
    '';
  });

  libintName = "new-cmake-2023-take2-b";
  libintRev = "577d295947c0baab8560a51fc437a3c992b5c5c9"; # Pinned commit from "new-cmake-2023-take2-b"
  libintSrc = fetchurl {
    url = "https://github.com/loriab/libint/archive/${libintRev}.zip";
    hash = "sha256-sulMRuGFAhpCzWd7nP4FC3IcI1oJsdYykTPI0MRgDN4=";
  };

  testInputs = {
    h2o_omp25_opt = writeTextFile {
      name = "h2o_omp25_opt";
      text = ''
        memory 1 GiB
        molecule Water {
        0 1
        O
        H 1 0.8
        H 1 0.8 2 110
        }

        set {
        basis cc-pvdz
        scf_type df
        mp_type df
        reference rhf
        }

        optimize("omp2.5")
      '';
    };

    BaF2_dft_grad = writeTextFile {
      name = "BaF2_dft_grad";
      text = ''
        memory 1 GiB
        molecule BaF2 {
          F
          Ba 1 1.5
          F  2 1.5 1 90
        }

        set {
          basis def2-TZVP
          relativistic dkh
          scf_type df
        }

        gradient("b3lyp-d3bj")
      '';
    };
  };

in
buildPythonPackage rec {
  pname = "psi4";
  version = "1.8.1";

  nativeBuildInputs = [
    cmake
    perl
    gfortran
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    boost
    gau2grid
    libxc
    blas
    lapack
    dkh_
    pcmsolver_
    libefp
    libecpint
    cppe
    chemps2_
    hdf5
    hdf5-cpp
    gmpxx
    eigen
  ];

  propagatedBuildInputs = [
    adcc
    pybind11
    qcelemental
    qcengine
    numpy
    pylibefp
    deepdiff
    dftd3
    chemps2_
    optking
    pytest
  ]
  ++ qcelemental.passthru.requiredPythonModules
  ++ qcengine.passthru.requiredPythonModules
  ++ lib.optional enableMrcc mrcc
  ++ lib.optional enableCfour cfour
  ;

  src = fetchFromGitHub {
    repo = pname;
    owner = "psi4";
    rev = "v${version}";
    hash = "sha256-q4m0W1UgSJycQ1s5Lhau/2RRX9jct41l7Gq8N68bboo=";
  };

  preConfigure = ''
    substituteInPlace ./*external/upstream/libint2/CMakeLists.txt \
      --replace "https://github.com/loriab/libint/archive/${libintName}.zip" "file://${libintSrc}" \
      --replace "-DWITH_ERI_MAX_AM:STRING=3;2;2" "-DWITH_ERI_MAX_AM:STRING=6;5;4" \
      --replace "-DWITH_ERI3_MAX_AM:STRING=4;3;3" "-DWITH_ERI3_MAX_AM:STRING=6;5;4" \
      --replace "-DWITH_ERI2_MAX_AM:STRING=4;3;3" "-DWITH_ERI2_MAX_AM:STRING=6;5;4" \
      --replace "-DWITH_MAX_AM:STRING=4;3;3" "-DWITH_MAX_AM:STRING=6;5;4"
  '';

  cmakeFlags = [
    "-DDCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF"
    "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF"
    "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON"
    "-DCMAKE_INSTALL_PREFIX=$out"
    "-DBUILD_SHARED_LIBS=ON"
    "-DENABLE_XHOST=OFF"
    "-DENABLE_OPENMP=ON"
    "-DBUILD_SHARED_LIBS=ON"
    # gau2grid
    "-DCMAKE_INSIST_FIND_PACKAGE_gau2grid=ON"
    "-Dgau2grid_DIR=${gau2grid}/share/cmake/gau2grid"
    # libint
    "-DMAX_AM_ERI=6"
    "-DBUILD_Libint2_GENERATOR=ON"
    # libxc
    "-DCMAKE_INSIST_FIND_PACKAGE_Libxc=ON"
    "-DLibxc_DIR=${libxc}/share/cmake/Libxc"
    # pcmsolver
    "-DCMAKE_INSIST_FIND_PACKAGE_PCMSolver=ON"
    "-DENABLE_PCMSolver=ON"
    "-DPCMSolver_DIR=${pcmsolver_}/share/cmake/PCMSolver"
    # DKH
    "-DENABLE_dkh=ON"
    "-DCMAKE_INSIST_FIND_PACKAGE_dkh=ON"
    "-Ddkh_DIR=${dkh_}/share/cmake/dkh"
    # CPPE
    "-DENABLE_cppe=ON"
    "-Dcppe_DIR=${cppe}"
    # LibEcpInt
    "-DENABLE_ecpint=ON"
    "-Decpint_DIR=${libecpint}"
    # LibEFP
    "-DENABLE_libefp=ON"
    # CheMPS2
    "-DENABLE_CheMPS2=ON"
    "-DCheMPS2_DIR=${chemps2_}"
    # ADCC
    "-DENABLE_adcc=ON"
    # Prefix path for all external packages
    "-DCMAKE_PREFIX_PATH=\"${gau2grid};${libxc};${qcelemental};${pcmsolver_};${dkh_};${libefp};${chemps2_};${libecpint};${cppe};${adcc}\""
  ];

  format = "other";
  enableParallelBuilding = true;

  configurePhase = ''
    runHook preConfigure

    cmake -Bbuild ${toString cmakeFlags} -DCMAKE_INSTALL_PREFIX=$out
    cd build

    runHook postConfigure
  '';

  postFixup =
    let
      binSearchPath = with lib; strings.makeSearchPath "bin" ([ dftd3 ]
        ++ lib.optional enableMrcc mrcc
        ++ lib.optional enableCfour cfour
      );

    in
    ''
      # Make libraries and external binaries available
      wrapProgram $out/bin/psi4 \
        --prefix PATH : ${binSearchPath}

      # Symlinks so that the lib directory is easy to find for python.
      mkdir -p $out/${python.sitePackages}
      ln -s $out/lib/psi4 $out/${python.sitePackages}/.

      # The symlink needs a fix for the PSIDATADIR on python side as its expecting to be installed
      # somewhere else.
      substituteInPlace $out/${python.sitePackages}/psi4/__init__.py \
        --replace 'elif "CMAKE_INSTALL_DATADIR" in data_dir:' 'else:' \
        --replace 'data_dir = os.path.sep.join([os.path.abspath(os.path.dirname(__file__)), "share", "psi4"])' 'data_dir = "@out@/share/psi4"' \
        --subst-var out
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    export OMP_NUM_THREADS=2
    $out/bin/psi4 -i ${testInputs.h2o_omp25_opt} -o h2o_omp25_opt.out -n 2 && grep "7     -76.23508523" h2o_omp25_opt.out
    $out/bin/psi4 -i ${testInputs.BaF2_dft_grad} -o BaF2_dft_grad.out -n 2
  '';

  meta = with lib; {
    description = "Open-Source Quantum Chemistry – an electronic structure package in C++ driven by Python";
    homepage = "http://www.psicode.org/";
    license = licenses.lgpl3;
    platforms = platforms.linux;
    maintainers = [ maintainers.sheepforce ];
  };
}
