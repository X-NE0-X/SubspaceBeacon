import importlib.util
import ipaddress
from pathlib import Path

p = Path(__file__).resolve().parents[1] / 'controller' / 'discover.py'
spec = importlib.util.spec_from_file_location('discover', p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_constants():
    assert mod.DEFAULT_PORT == 22022
    assert mod.DEFAULT_USER == 'ORION-RELAY'


def test_network_shape():
    net = ipaddress.ip_network('192.168.1.23/24', strict=False)
    assert str(net) == '192.168.1.0/24'
    assert len(list(net.hosts())) == 254


def test_windows_route_parser_ignores_proxy_and_wsl_routes():
    route_text = '''
          0.0.0.0          0.0.0.0      192.168.1.1    192.168.1.161     45
          0.0.0.0        192.0.0.0       198.18.0.2       198.18.0.1      0
        172.24.224.0    255.255.240.0         On-link      172.24.224.1   5256
      192.168.1.0    255.255.255.0         On-link     192.168.1.161    301
       198.18.0.0    255.255.255.252         On-link        198.18.0.1    256
    '''
    connected, defaults = mod._parse_windows_route_table(route_text)
    assert defaults == {'192.168.1.161'}
    assert [(str(network), interface) for network, interface, _ in connected] == [
        ('172.24.224.0/20', '172.24.224.1'),
        ('192.168.1.0/24', '192.168.1.161'),
    ]


def test_windows_route_selection_prefers_default_gateway_interface():
    route_text = '''
          0.0.0.0          0.0.0.0      192.168.1.1    192.168.1.161     45
      192.168.1.0    255.255.255.0         On-link     192.168.1.161    301
        172.24.224.0    255.255.240.0         On-link      172.24.224.1   5256
    '''
    connected, defaults = mod._parse_windows_route_table(route_text)
    selected = [item for item in connected if item[1] in defaults]
    assert [(str(network), interface) for network, interface, _ in selected] == [
        ('192.168.1.0/24', '192.168.1.161'),
    ]
