{ lib
, buildPythonPackage
, fetchPypi
, isPy27
, packaging
, pytestCheckHook
, nose
, numpy
, h5py
, pydicom
, scipy
}:

buildPythonPackage rec {
  pname = "nibabel";
  version = "3.2.2";
  disabled = isPy27;

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-sNzBdLMEBc6ej+weqzy7sg9cXkkgl2wIsi4FC3wST5Q=";
  };

  propagatedBuildInputs = [ numpy scipy h5py packaging pydicom ];

  checkInputs = [
    pytestCheckHook
  ];

  disabledTests = [
    # https://github.com/nipy/nibabel/issues/951
    "test_filenames"
  ];

  meta = with lib; {
    homepage = "https://nipy.org/nibabel";
    description = "Access a multitude of neuroimaging data formats";
    license = licenses.mit;
    maintainers = with maintainers; [ ashgillman ];
  };
}
