"""Compile positive/negative consumer fixtures against the actual client checkout."""
from pathlib import Path
import shutil
import subprocess
import tempfile


def check_api_shape(package):
    package = Path(package).resolve()
    build = package/'build'
    build.mkdir(exist_ok=True)
    imports = "import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';\n"
    cases = {
        'static_consumer': ("final bool Function(String, bool, {EvaluationOptions? options}) evaluate = OpenFeatureAPI.instance.getClient().getBooleanValue; evaluate('flag', false);", None),
        'no_transaction_propagator': ("OpenFeatureAPI.instance.setTransactionContextPropagator(null);", 'UNDEFINED_METHOD'),
        'no_client_context': ("OpenFeatureAPI.instance.getClient().setEvaluationContext(EvaluationContext.empty);", 'UNDEFINED_METHOD'),
        'no_invocation_context': ("OpenFeatureAPI.instance.getClient().getBooleanValue('flag', false, context: EvaluationContext.empty);", 'UNDEFINED_NAMED_PARAMETER'),
    }
    results = []
    with tempfile.TemporaryDirectory(prefix='client-api-shape-',dir=build) as directory:
        location = Path(directory).resolve()
        if not location.is_relative_to(build.resolve()):
            raise RuntimeError('Fixture directory escaped its package build directory')
        for name, (body, expected) in cases.items():
            fixture = location/(name+'.dart')
            fixture.write_text(imports+'void main() { '+body+' }\n',encoding='utf-8')
            command = [shutil.which('dart'),'analyze','--format=machine',str(fixture)]
            result = subprocess.run(command,cwd=package,stdout=subprocess.PIPE,stderr=subprocess.PIPE,encoding='utf-8')
            diagnostics = (result.stdout+'\n'+result.stderr).strip()
            codes = [line.split('|')[2] for line in diagnostics.splitlines() if line.startswith('ERROR|')]
            passed = (result.returncode == 0 and not codes) if expected is None else (result.returncode != 0 and codes == [expected])
            results.append({'name':name,'passed':passed,'expected_error':expected,'process_exit_code':result.returncode,'diagnostics':diagnostics})
    return results
