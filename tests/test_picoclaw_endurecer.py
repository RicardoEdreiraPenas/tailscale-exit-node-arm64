"""Pruebas de la configuración segura de PicoClaw (python3 -m unittest)."""

import copy
import importlib.util
import json
import os
import tempfile
import unittest

RUTA = os.path.join(os.path.dirname(__file__), "..", "scripts", "picoclaw_endurecer.py")
spec = importlib.util.spec_from_file_location("endurecer", RUTA)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

BASE = {
    "version": 3,
    "agents": {"defaults": {"workspace": "~/.picoclaw/workspace", "restrict_to_workspace": False}},
    "channel_list": {
        "telegram": {"enabled": True, "type": "telegram", "allow_from": ["123456789"],
                     "settings": {"token": ""}},
        "discord": {"enabled": False, "allow_from": []},
    },
    "tools": {
        "exec": {"enabled": True, "enable_deny_patterns": False},
        "cron": {"enabled": True, "allow_command": True},
        "web_fetch": {"enabled": True},
        "read_file": {"enabled": True},
    },
    "gateway": {"host": "0.0.0.0", "port": 18790},
}


def endurecer(cfg, permitir=False):
    cfg = copy.deepcopy(cfg)
    problemas = mod.endurecer(cfg, "/var/lib/picoclaw/workspace", permitir)
    return cfg, problemas


class Pruebas(unittest.TestCase):
    def test_configuracion_valida_queda_cerrada(self):
        cfg, problemas = endurecer(BASE)
        self.assertEqual(problemas, [])
        self.assertFalse(cfg["tools"]["exec"]["enabled"])
        self.assertFalse(cfg["tools"]["cron"]["enabled"])
        self.assertFalse(cfg["tools"]["web_fetch"]["enabled"])
        self.assertTrue(cfg["tools"]["read_file"]["enabled"])
        self.assertTrue(cfg["agents"]["defaults"]["restrict_to_workspace"])
        self.assertEqual(cfg["gateway"]["host"], "127.0.0.1")
        self.assertEqual(cfg["tools"]["allow_write_paths"], [])

    def test_lista_vacia_es_un_problema(self):
        cfg = copy.deepcopy(BASE)
        cfg["channel_list"]["telegram"]["allow_from"] = []
        _, problemas = endurecer(cfg)
        self.assertTrue(any("allow_from" in p for p in problemas))

    def test_comodin_y_valor_de_ejemplo_son_problemas(self):
        for valor in (["*"], ["YOUR_USER_ID"], ["123456789", "*"]):
            cfg = copy.deepcopy(BASE)
            cfg["channel_list"]["telegram"]["allow_from"] = valor
            _, problemas = endurecer(cfg)
            self.assertTrue(problemas, valor)

    def test_telegram_exige_id_numerico(self):
        cfg = copy.deepcopy(BASE)
        cfg["channel_list"]["telegram"]["allow_from"] = ["@ricardo"]
        _, problemas = endurecer(cfg)
        self.assertTrue(any("numérico" in p for p in problemas))

    def test_sin_canales_activos_es_un_problema(self):
        cfg = copy.deepcopy(BASE)
        cfg["channel_list"]["telegram"]["enabled"] = False
        _, problemas = endurecer(cfg)
        self.assertTrue(problemas)

    def test_configuracion_antigua_se_rechaza(self):
        cfg = copy.deepcopy(BASE)
        cfg["version"] = 1
        _, problemas = endurecer(cfg)
        self.assertTrue(problemas)

    def test_permitir_comandos_activa_los_filtros(self):
        cfg, problemas = endurecer(BASE, permitir=True)
        self.assertEqual(problemas, [])
        self.assertTrue(cfg["tools"]["exec"]["enabled"])
        self.assertTrue(cfg["tools"]["exec"]["enable_deny_patterns"])

    def test_script_completo_escribe_con_permisos_600(self):
        with tempfile.TemporaryDirectory() as d:
            home = os.path.join(d, ".picoclaw")
            os.makedirs(home)
            with open(os.path.join(home, "config.json"), "w") as f:
                json.dump(BASE, f)
            with open(os.path.join(home, ".security.yml"), "w") as f:
                f.write("channels:\n  telegram:\n    token: x\n")
            import subprocess, sys
            r = subprocess.run([sys.executable, RUTA, "--home", home, "--workspace", d + "/ws"],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(os.stat(os.path.join(home, "config.json")).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(os.path.join(home, ".security.yml")).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(home).st_mode & 0o777, 0o700)
            with open(os.path.join(home, "config.json")) as f:
                self.assertFalse(json.load(f)["tools"]["exec"]["enabled"])


class PruebasRevision(unittest.TestCase):
    def test_agentes_con_nombre_tambien_quedan_limitados(self):
        cfg = copy.deepcopy(BASE)
        cfg["agents"]["list"] = [{"name": "otro", "workspace": "/", "restrict_to_workspace": False}]
        cfg, problemas = endurecer(cfg)
        self.assertEqual(problemas, [])
        self.assertTrue(cfg["agents"]["list"][0]["restrict_to_workspace"])
        self.assertEqual(cfg["agents"]["list"][0]["workspace"], "/var/lib/picoclaw/workspace")

    def test_canales_con_puerto_propio_se_desactivan(self):
        cfg = copy.deepcopy(BASE)
        cfg["channel_list"]["maixcam"] = {"enabled": True, "allow_from": ["1"],
                                          "settings": {"host": "0.0.0.0", "port": 18790}}
        cfg, problemas = endurecer(cfg)
        self.assertEqual(problemas, [])
        self.assertFalse(cfg["channel_list"]["maixcam"]["enabled"])

    def test_hooks_y_comandos_de_cron_desactivados(self):
        cfg, _ = endurecer(BASE)
        self.assertFalse(cfg["hooks"]["enabled"])
        self.assertFalse(cfg["tools"]["cron"]["allow_command"])

    def test_configurar_desde_entrada_estandar(self):
        cfg = copy.deepcopy(BASE)
        cfg["channel_list"]["telegram"]["allow_from"] = []
        mod.configurar(cfg, {"token": "1:x", "chat_id": "555666777", "api_key": "k", "modelo": "gemini-2.5-flash"})
        cfg2, problemas = endurecer(cfg)
        self.assertEqual(problemas, [])
        self.assertEqual(cfg2["channel_list"]["telegram"]["allow_from"], ["555666777"])
        self.assertEqual(cfg2["agents"]["defaults"]["model_name"], "gemini-2.5-flash")
        modelo = [m for m in cfg2["model_list"] if m["model_name"] == "gemini-2.5-flash"][0]
        self.assertEqual(modelo["provider"], "gemini")

    def test_rechaza_configuracion_que_es_un_enlace(self):
        import subprocess, sys
        with tempfile.TemporaryDirectory() as d:
            home = os.path.join(d, ".picoclaw"); os.makedirs(home)
            otro = os.path.join(d, "otro.json")
            with open(otro, "w") as f:
                json.dump(BASE, f)
            os.symlink(otro, os.path.join(home, "config.json"))
            r = subprocess.run([sys.executable, RUTA, "--home", home], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
