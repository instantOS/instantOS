"""Keep the offline manifest parser compatible with installer commands."""
import subprocess
import unittest
from pathlib import Path


class PackageListParserTests(unittest.TestCase):
    def collect(self, commands):
        script = (Path(__file__).resolve().parents[1] / "offline/mk-package-list.sh").read_text()
        function = script.split("collect_packages() {", 1)[1].split(
            "# --- variant definitions", 1
        )[0]
        result = subprocess.run(
            ["bash", "-c", "collect_packages() {" + function + "\ncollect_packages"],
            input=commands, text=True, capture_output=True, check=True,
        )
        return result.stdout.splitlines()

    def test_installer_commands_with_configuration_paths(self):
        commands = """[DRY RUN] pacstrap -C /tmp/installer/pacstrap.conf -M /mnt base linux
[DRY RUN] pacman --config /etc/pacman.conf -S --noconfirm --needed fuzzel swaybg noto-fonts
[DRY RUN] pacman --config /etc/pacman.conf -Sy archlinux-keyring
[DRY RUN] pacman --sysroot /mnt -Scc --noconfirm
"""
        self.assertEqual(self.collect(commands), ["base", "linux", "fuzzel", "swaybg", "noto-fonts"])

    def test_plain_commands_remain_supported(self):
        self.assertEqual(
            self.collect("[DRY RUN] pacstrap /mnt base\n[DRY RUN] pacman -S --needed instantos\n"),
            ["base", "instantos"],
        )


if __name__ == "__main__":
    unittest.main()
