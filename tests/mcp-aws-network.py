#!/usr/bin/env python3
"""Exercise the production AWS MCP rule reconciler without cloud writes."""

import ipaddress
import unittest
from pathlib import Path


class EC2:
    def __init__(self, rules):
        self.rules = rules
        self.added = []
        self.removed = []

    def describe_security_groups(self, **kwargs):
        return {"SecurityGroups": [{"GroupId": "sg-owned", "Tags": []}]}

    def describe_security_group_rules(self, **kwargs):
        return {"SecurityGroupRules": self.rules}

    def revoke_security_group_ingress(self, **kwargs):
        self.removed.extend(kwargs["SecurityGroupRuleIds"])

    def authorize_security_group_ingress(self, **kwargs):
        self.added.extend(kwargs["IpPermissions"][0]["IpRanges"])


def rule(cidr, description="demojam-ao-mcp"):
    return {"SecurityGroupRuleId": cidr, "CidrIpv4": cidr, "Description": description,
            "IsEgress": False, "IpProtocol": "tcp", "FromPort": 8443, "ToPort": 8443}


class AWSMCPRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (Path(__file__).resolve().parents[1] / "bootstrap/bootstrap.sh").read_text()
        block = source.split("if action in ('mcp-open', 'mcp-close'):", 1)[1]
        block = block.split("if action in ('cleanup', 'teardown'):", 1)[0]
        cls.code = compile("if True:" + block, "bootstrap AWS MCP reconciler", "exec")

    def reconcile(self, rules, action="mcp-open", ips="8.8.8.8"):
        ec2 = EC2(rules)
        namespace = {"action": action, "state": {"webapp_security_group_id": "sg-owned"},
                     "env": {"DEMO_MCP_EGRESS_IPS": ips}, "ec2": ec2,
                     "ipaddress": ipaddress, "owned": lambda group: None,
                     "sys": __import__("sys")}
        with self.assertRaises(SystemExit) as result:
            exec(self.code, namespace)
        self.assertEqual(result.exception.code, 0)
        return ec2

    def test_repeated_discovery_does_not_add_rules(self):
        ec2 = self.reconcile([rule("8.8.8.8/32")], ips="8.8.8.8,8.8.8.8")
        self.assertEqual(ec2.added, [])
        self.assertEqual(ec2.removed, [])

    def test_egress_change_removes_stale_rule(self):
        ec2 = self.reconcile([rule("1.1.1.1/32")])
        self.assertEqual(ec2.removed, ["1.1.1.1/32"])
        self.assertEqual(ec2.added, [{"CidrIp": "8.8.8.8/32", "Description": "demojam-ao-mcp"}])

    def test_disable_closes_owned_port(self):
        ec2 = self.reconcile([rule("8.8.8.8/32")], action="mcp-close")
        self.assertEqual(ec2.removed, ["8.8.8.8/32"])
        self.assertEqual(ec2.added, [])

    def test_refuses_broad_private_and_foreign_rules(self):
        for address in ["0.0.0.0/0", "10.0.0.1", "::1", ""]:
            with self.subTest(address=address), self.assertRaises((AssertionError, ValueError)):
                self.reconcile([], ips=address)
        with self.assertRaisesRegex(AssertionError, "Unowned rule"):
            self.reconcile([rule("0.0.0.0/0", description="foreign")])


if __name__ == "__main__":
    unittest.main()
