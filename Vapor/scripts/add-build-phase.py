#!/usr/bin/env python3
import re
import uuid


def generate_id():
    return "".join(str(uuid.uuid4()).upper().split("-"))[:24]


project_path = "Vapor.xcodeproj/project.pbxproj"

with open(project_path, "r") as f:
    content = f.read()

script_id = generate_id()
script_phase = (
    """/* Begin PBXShellScriptBuildPhase section */
		"""
    + script_id
    + """ /* Copy Ollama Binary */ = {
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/Resources/ollama",
			);
			name = "Copy Ollama Binary";
			outputFileListPaths = (
			);
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Resources/ollama",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "if [ -f \\"$SRCROOT/Resources/ollama\\" ]; then\\n    cp \\"$SRCROOT/Resources/ollama\\" \\"$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/ollama\\"\\n    chmod +x \\"$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/ollama\\"\\nfi\\n";
			showEnvVarsInLog = 0;
		};
/* End PBXShellScriptBuildPhase section */
"""
)

content = content.replace(
    "/* End PBXResourcesBuildPhase section */",
    "/* End PBXResourcesBuildPhase section */\n" + script_phase,
)

build_phases_pattern = r"(508498382F86F964008E324C /\* Vapor \*/ = \{[^}]*?buildPhases = \(\s*)(508498352F86F964008E324C /\* Sources \*/,)"
replacement = r"\1" + script_id + r" /* Copy Ollama Binary */,\n\t\t\t\t" + r"\2"

content = re.sub(build_phases_pattern, replacement, content, flags=re.DOTALL)

with open(project_path, "w") as f:
    f.write(content)

print(f"Added build phase with ID: {script_id}")
