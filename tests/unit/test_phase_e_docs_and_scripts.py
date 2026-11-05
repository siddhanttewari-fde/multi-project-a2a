"""Unit tests for Phase E documentation, slides, and verification scripts."""

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def test_phase_e_documentation_files_exist_and_cover_core_topics() -> None:
    """Verify Cloud Console testing guide, executive slides, and README exist."""
    testing_guide = REPO_ROOT / "docs" / "cloud-console-testing-guide.md"
    slides_doc = REPO_ROOT / "docs" / "enterprise-a2a-slides.md"
    readme_doc = REPO_ROOT / "README.md"

    assert testing_guide.is_file()
    assert slides_doc.is_file()
    assert readme_doc.is_file()

    guide_text = testing_guide.read_text(encoding="utf-8")
    assert "central-egress-gw" in guide_text
    assert "networkservices.googleapis.com/Gateway" in guide_text
    assert "custom.allowlistedEgressAgentGatewaysForAgentEngine" in guide_text
    assert "verify_e2e_a2a.sh" in guide_text

    slides_text = slides_doc.read_text(encoding="utf-8")
    assert "Slide 1:" in slides_text
    assert "Slide 2:" in slides_text
    assert "Slide 3:" in slides_text
    assert "VPC Service Controls" in slides_text
    assert "SPIFFE" in slides_text


def test_phase_e_scripts_have_valid_bash_syntax() -> None:
    """Verify all shell scripts in scripts/ pass bash -n syntax validation."""
    scripts_dir = REPO_ROOT / "scripts"
    shell_scripts = sorted(scripts_dir.glob("*.sh"))
    assert len(shell_scripts) >= 4

    for script in shell_scripts:
        result = subprocess.run(
            ["bash", "-n", str(script)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, f"Syntax error in {script.name}: {result.stderr}"
