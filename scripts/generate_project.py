#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
import hashlib
import json
import plistlib
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
objects = {}


def identifier(label):
    return hashlib.sha256(label.replace(str(ROOT), "").encode()).hexdigest()[:24].upper()


def add(label, **fields):
    key = identifier(label)
    objects[key] = fields
    return key


def literal(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + json.dumps(k) + " = " + literal(v, level + 1) + ";\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + literal(v, level + 1) + ",\n" for v in value) + "\t" * level + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value), ensure_ascii=True)


def file_ref(path):
    name = path.name
    types = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcprivacy": "text.xml", ".xcconfig": "text.xcconfig", ".md": "net.daringfireball.markdown"}
    file_type = "folder.assetcatalog" if name.endswith(".xcassets") else types.get(path.suffix, "text")
    return add(str(path), isa="PBXFileReference", lastKnownFileType=file_type, path=name, sourceTree="<group>")


def group(path):
    children = []
    for child in sorted(path.iterdir()):
        if child.name.startswith("."):
            continue
        if child.is_dir() and child.suffix != ".xcassets":
            children.append(group(child))
        else:
            children.append(file_ref(child))
    return add("group:" + str(path), isa="PBXGroup", children=children, path=path.name, sourceTree="<group>")


def configs(label, settings, base=None):
    config_ids = []
    for mode in ("Debug", "Release"):
        values = dict(settings)
        values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"})
        if mode == "Debug":
            values.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES"})
        else:
            values.update({"SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
        fields = dict(isa="XCBuildConfiguration", buildSettings=values, name=mode)
        if base:
            fields["baseConfigurationReference"] = base
        config_ids.append(add(label + ":" + mode, **fields))
    return add(label + ":configurations", isa="XCConfigurationList", buildConfigurations=config_ids, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def build_phase(label, isa, paths):
    files = []
    for path in paths:
        files.append(add(label + ":" + str(path), isa="PBXBuildFile", fileRef=identifier(str(path))))
    return add(label, isa=isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)


source_groups = [group(ROOT / name) for name in ("Ember", "EmberTests", "EmberUITests")]
config_file = file_ref(ROOT / "Config.xcconfig")
readme = file_ref(ROOT / "README.md")
products = []
target_ids = []
project_id = identifier("project")
app_id = identifier("target:Ember")
common = {
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES", "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES", "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE", "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
}
project_configs = configs("project", common, base=config_file)

for name, kind in (("Ember", "application"), ("EmberTests", "bundle.unit-test"), ("EmberUITests", "bundle.ui-testing")):
    app = name == "Ember"
    product = add("product:" + name, isa="PBXFileReference", explicitFileType="wrapper.application" if app else "wrapper.cfbundle", includeInIndex=0, path=name + (".app" if app else ".xctest"), sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    paths = sorted((ROOT / name).rglob("*.swift"))
    sources = build_phase(name + ":sources", "PBXSourcesBuildPhase", paths)
    resources = build_phase(name + ":resources", "PBXResourcesBuildPhase", [ROOT / "Ember/Resources/Assets.xcassets", ROOT / "Ember/Resources/PrivacyInfo.xcprivacy"] if app else [])
    frameworks = build_phase(name + ":frameworks", "PBXFrameworksBuildPhase", [])
    settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "GENERATE_INFOPLIST_FILE": "YES"}
    if app:
        settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(EMBER_BUNDLE_ID)", "INFOPLIST_FILE": "Ember/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"], "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1", "SWIFT_EMIT_LOC_STRINGS": "YES"})
    else:
        settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(EMBER_BUNDLE_ID)." + name, "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]})
        if name == "EmberTests":
            settings.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Ember.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Ember", "BUNDLE_LOADER": "$(TEST_HOST)"})
        else:
            settings["TEST_TARGET_NAME"] = "Ember"
    dependencies = []
    if not app:
        proxy = add(name + ":proxy", isa="PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_id, remoteInfo="Ember")
        dependencies.append(add(name + ":dependency", isa="PBXTargetDependency", target=app_id, targetProxy=proxy))
    target_ids.append(add("target:" + name, isa="PBXNativeTarget", buildConfigurationList=configs(name, settings), buildPhases=[sources, frameworks, resources], buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product, productType="com.apple.product-type." + kind))

product_group = add("products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("main", isa="PBXGroup", children=source_groups + [config_file, readme, product_group], sourceTree="<group>")
add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600", "TargetAttributes": {app_id: {"CreatedOnToolsVersion": "26.0"}, identifier("target:EmberTests"): {"CreatedOnToolsVersion": "26.0", "TestTargetID": app_id}, identifier("target:EmberUITests"): {"CreatedOnToolsVersion": "26.0", "TestTargetID": app_id}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=target_ids)

project = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}
project_dir = ROOT / "Ember.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + literal(project) + "\n")


def reference(name):
    ext = ".app" if name == "Ember" else ".xctest"
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier("target:" + name)}" BuildableName="{name}{ext}" BlueprintName="{name}" ReferencedContainer="container:Ember.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("Ember")}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" codeCoverageEnabled="YES">
  <Testables><TestableReference skipped="NO" parallelizable="NO">{reference("EmberTests")}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{reference("EmberUITests")}</TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Ember")}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Ember")}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_path = project_dir / "xcshareddata/xcschemes"
scheme_path.mkdir(parents=True, exist_ok=True)
(scheme_path / "Ember.xcscheme").write_text(scheme)
workspace = project_dir / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
print(f"Generated {len(objects)} project objects, {len(target_ids)} targets.")
