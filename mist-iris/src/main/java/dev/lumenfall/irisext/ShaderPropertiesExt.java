package dev.lumenfall.irisext;

import it.unimi.dsi.fastutil.ints.Int2IntMap;

import java.util.Map;

public interface ShaderPropertiesExt {
	Int2IntMap lumen$neighborGroups();

	Map<String, String> lumen$keys();
}
