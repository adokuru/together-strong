"""Generate the dependency-free Xcode project from checked-in Swift sources."""
from pathlib import Path
from hashlib import sha256
import json

root = Path(__file__).resolve().parent.parent / 'ios'
objects = {}
def identity(name): return sha256(name.encode()).hexdigest()[:24].upper()
def add(identifier, isa, **fields):
    key = identity(identifier)
    objects[key] = {'isa': isa, **fields}
    return key

def ref(value): return ('ref', value)
def encode(value):
    if isinstance(value, tuple): return value[1]
    if isinstance(value, dict): return '{ ' + ' '.join(f'{json.dumps(k)} = {encode(v)};' for k,v in value.items()) + ' }'
    if isinstance(value, list): return '( ' + ', '.join(encode(v) for v in value) + ' )'
    return json.dumps(str(value))

products = []
groups = []
configs = {}
for name in ['Debug', 'Release']:
    configs[name] = add('config-file-'+name, 'PBXFileReference', lastKnownFileType='text.xcconfig', path='Configuration/'+name+'.xcconfig', sourceTree='SOURCE_ROOT')
config_group = add('configuration', 'PBXGroup', name='Configuration', children=[ref(x) for x in configs.values()], sourceTree='<group>')
groups.append(ref(config_group))
project_settings = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='6.0',
    CLANG_ENABLE_MODULES='YES', SWIFT_STRICT_CONCURRENCY='complete',
    SWIFT_APPROACHABLE_CONCURRENCY='YES', SWIFT_DEFAULT_ACTOR_ISOLATION='MainActor')
proj_configs = []
for mode in ['Debug','Release']:
    settings = {**project_settings, 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode=='Debug' else '-O',
                'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode=='Debug' else 'dwarf-with-dsym',
                'ENABLE_TESTABILITY': 'YES' if mode=='Debug' else 'NO'}
    if mode=='Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
    proj_configs.append(ref(add('project-'+mode, 'XCBuildConfiguration', name=mode, buildSettings=settings)))
proj_config_list = add('project-configs', 'XCConfigurationList', buildConfigurations=proj_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

targets = []
for target, kind in [('TogetherStrong','application'),('TogetherStrongTests','bundle.unit-test'),('TogetherStrongUITests','bundle.ui-testing')]:
    sources=[]; children=[]; resources=[]
    for file in sorted((root/target).rglob('*.swift')):
        relative = str(file.relative_to(root))
        file_id = add('file-'+relative, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=relative, sourceTree='SOURCE_ROOT')
        children.append(ref(file_id))
        sources.append(ref(add('build-'+relative, 'PBXBuildFile', fileRef=ref(file_id))))
    if target=='TogetherStrongTests':
        file_id=add('fixture', 'PBXFileReference', lastKnownFileType='text.json', path='../contracts/fixtures/workout-v1.json', sourceTree='SOURCE_ROOT')
        children.append(ref(file_id))
        resources.append(ref(add('fixture-build','PBXBuildFile',fileRef=ref(file_id))))
    groups.append(ref(add('group-'+target, 'PBXGroup', name=target, children=children, sourceTree='<group>')))
    product = add('product-'+target, 'PBXFileReference', explicitFileType='wrapper.application' if kind=='application' else 'wrapper.cfbundle', path=target+('.app' if kind=='application' else '.xctest'), sourceTree='BUILT_PRODUCTS_DIR')
    products.append(ref(product))
    phases = [ref(add('sources-'+target, 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=sources, runOnlyForDeploymentPostprocessing='0')),
              ref(add('frameworks-'+target, 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')),
              ref(add('resources-'+target, 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=resources, runOnlyForDeploymentPostprocessing='0'))]
    configurations=[]
    for mode in ['Debug','Release']:
        settings=dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='com.togetherstrong.private'+('' if kind=='application' else '.'+target),
            TARGETED_DEVICE_FAMILY='1', CODE_SIGN_STYLE='Automatic', CURRENT_PROJECT_VERSION='1', MARKETING_VERSION='0.1.0',
            SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO')
        if kind=='application': settings.update(INFOPLIST_FILE='Configuration/Info.plist', GENERATE_INFOPLIST_FILE='NO')
        else:
            settings.update(GENERATE_INFOPLIST_FILE='YES')
            if kind=='bundle.unit-test': settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/TogetherStrong.app/TogetherStrong', BUNDLE_LOADER='$(TEST_HOST)')
            else: settings.update(TEST_TARGET_NAME='TogetherStrong')
        configurations.append(ref(add(target+'-'+mode, 'XCBuildConfiguration', name=mode, baseConfigurationReference=ref(configs[mode]), buildSettings=settings)))
    config_list=add('configs-'+target, 'XCConfigurationList', buildConfigurations=configurations, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
    dependencies=[]
    if kind!='application':
        proxy=add('proxy-'+target, 'PBXContainerItemProxy', containerPortal=ref(identity('project')), proxyType='1', remoteGlobalIDString=ref(identity('target-TogetherStrong')), remoteInfo='TogetherStrong')
        dependencies=[ref(add('dependency-'+target,'PBXTargetDependency',target=ref(identity('target-TogetherStrong')),targetProxy=ref(proxy)))]
    targets.append(ref(add('target-'+target, 'PBXNativeTarget', buildConfigurationList=ref(config_list), buildPhases=phases, buildRules=[], dependencies=dependencies, name=target, productName=target, productReference=ref(product), productType='com.apple.product-type.'+kind)))
product_group=add('products','PBXGroup', name='Products', children=products, sourceTree='<group>')
main_group=add('main','PBXGroup', children=groups+[ref(product_group)], sourceTree='<group>')
project=add('project','PBXProject', attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2660'}, buildConfigurationList=ref(proj_config_list), compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en','Base'], mainGroup=ref(main_group), productRefGroup=ref(product_group), projectDirPath='', projectRoot='', targets=targets)
project_dir=root/'TogetherStrong.xcodeproj'
project_dir.mkdir(exist_ok=True)
text='// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
text+='\n'.join(f'  {key} = {encode(value)};' for key,value in objects.items())
text+='\n };\n rootObject = '+project+';\n}\n'
(project_dir/'project.pbxproj').write_text(text)
scheme_dir=project_dir/'xcshareddata'/'xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
def build_ref(target):
    extension='.app' if target=='TogetherStrong' else '.xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identity("target-"+target)}" BuildableName="{target+extension}" BlueprintName="{target}" ReferencedContainer="container:TogetherStrong.xcodeproj"/>'
scheme='''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'''
for target in ['TogetherStrong','TogetherStrongTests','TogetherStrongUITests']:
    scheme+='<BuildActionEntry buildForTesting="YES" buildForRunning="'+('YES' if target=='TogetherStrong' else 'NO')+'" buildForProfiling="NO" buildForArchiving="'+('YES' if target=='TogetherStrong' else 'NO')+'" buildForAnalyzing="YES">'+build_ref(target)+'</BuildActionEntry>'
scheme+='''</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO"><Testables>'''
for target in ['TogetherStrongTests','TogetherStrongUITests']: scheme+='<TestableReference skipped="NO">'+build_ref(target)+'</TestableReference>'
scheme+='''</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'''+build_ref('TogetherStrong')+'''</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'''+build_ref('TogetherStrong')+'''</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(scheme_dir/'TogetherStrong.xcscheme').write_text(scheme)
print('Generated TogetherStrong.xcodeproj with application, unit-test and UI-test targets.')
