/*
 * GeoGebra - Dynamic Mathematics for Everyone
 * Copyright (c) GeoGebra GmbH, Altenbergerstr. 69, 4040 Linz, Austria
 * https://www.geogebra.org
 *
 * This file is licensed by GeoGebra GmbH under the EUPL 1.2 licence and
 * may be used under the EUPL 1.2 in compatible projects (see Article 5
 * and the Appendix of EUPL 1.2 for details).
 * You may obtain a copy of the licence at:
 * https://interoperable-europe.ec.europa.eu/collection/eupl/eupl-text-eupl-12
 *
 * Note: The overall GeoGebra software package is free to use for
 * non-commercial purposes only.
 * See https://www.geogebra.org/license for full licensing details
 */

package org.geogebra.common.gui.toolbar;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;

import org.junit.jupiter.api.Test;

class ToolbarMacroTest {

	@Test
	void appendsMacrosToPerspectiveToolbar() {
		assertEquals(
				"0 1 | 2 | 100001 100002",
				ToolBar.addMacroModes("0 1 | 2", List.of(100001, 100002)));
	}

	@Test
	void doesNotDuplicateMacrosAlreadyInToolbar() {
		assertEquals(
				"0 1 | 2 | 100002 100001",
				ToolBar.addMacroModes("0 1 | 2 | 100001", List.of(100001, 100002)));
	}
}
