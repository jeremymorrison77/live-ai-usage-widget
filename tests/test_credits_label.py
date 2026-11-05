"""Guard both credits layouts against reverting to a same-size title."""
import unittest
from pathlib import Path

class CreditsLabelTests(unittest.TestCase):
    def test_shared_title_uses_existing_row_font_sizes(self):
        source = (Path(__file__).resolve().parents[1] / "Shared/StatusView.swift").read_text()
        title = source.split("private var creditsTitle: some View {", 1)[1].split("/// One name size", 1)[0]
        self.assertIn('HStack(alignment: .firstTextBaseline, spacing: 0)', title)
        self.assertIn("Group {", title)
        self.assertIn('Text("Grok")', title)
        self.assertIn('Text(" · " + "Credits").font(.system(size: labelSize))', title)
        layouts = source.split("if let amount = credits(agent)", 1)[1].split("private var creditsTitle", 1)[0]
        self.assertEqual(layouts.count("creditsTitle"), 2)
        self.assertNotIn('Text("Grok credits")', layouts)
