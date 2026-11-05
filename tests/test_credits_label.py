"""Guard the shared credits title and amount typography."""
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
        layouts = source.split("if credits(agent) != nil", 1)[1].split("private var creditsTitle", 1)[0]
        self.assertEqual(layouts.count("creditsTitle"), 2)
        self.assertNotIn('Text("Grok credits")', layouts)

    def test_denominator_matches_amount_and_burn_stays_small(self):
        source = (Path(__file__).resolve().parents[1] / "Shared/StatusView.swift").read_text()
        amount = source.split("private func creditsAmount(_ usage: AgentUsage?) -> Text {", 1)[1].split("private var creditsTitle", 1)[0]
        self.assertIn('Text(usage?.creditsDenominator ?? "").font(.system(size: nameSize))', amount)
        self.assertIn('Text(usage?.creditsBurn ?? "").font(.system(size: labelSize))', amount)
        # Both dollar components inherit the same weight and colour from their row.
        self.assertNotIn('fontWeight', amount)
        self.assertNotIn('foregroundStyle', amount)
