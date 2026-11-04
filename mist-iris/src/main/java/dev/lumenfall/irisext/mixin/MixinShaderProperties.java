package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.ShaderPropertiesExt;
import it.unimi.dsi.fastutil.ints.Int2IntMap;
import it.unimi.dsi.fastutil.ints.Int2IntOpenHashMap;
import net.irisshaders.iris.helpers.StringPair;
import net.irisshaders.iris.shaderpack.option.ShaderPackOptions;
import net.irisshaders.iris.shaderpack.properties.ShaderProperties;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.util.HashMap;
import java.util.Map;

@Mixin(value = ShaderProperties.class, remap = false)
public class MixinShaderProperties implements ShaderPropertiesExt {
	@Unique private Int2IntOpenHashMap lumen$groups;
	@Unique private Map<String, String> lumen$keys;

	@Inject(method = "<init>(Ljava/lang/String;Lnet/irisshaders/iris/shaderpack/option/ShaderPackOptions;Ljava/lang/Iterable;)V", at = @At("TAIL"))
	private void lumen$readGroups(String contents, ShaderPackOptions options, Iterable<StringPair> defines, CallbackInfo ci) {
		lumen$groups = new Int2IntOpenHashMap();
		lumen$keys = new HashMap<>();
		int group = 0;
		for (String line : contents.split("\\R")) {
			String l = line.trim();
			int eq = l.indexOf('=');
			if (eq < 0) continue;
			if (l.startsWith("lumenfall.")) {
				lumen$keys.put(l.substring(0, eq).trim(), l.substring(eq + 1).trim());
				continue;
			}
			if (!l.startsWith("neighbors.group.")) continue;
			for (String id : l.substring(eq + 1).trim().split("\\s+")) {
				try {
					lumen$groups.put(Integer.parseInt(id), group);
				} catch (NumberFormatException ignored) {
				}
			}
			group++;
		}
	}

	@Override
	public Int2IntMap lumen$neighborGroups() {
		return lumen$groups != null ? lumen$groups : new Int2IntOpenHashMap();
	}

	@Override
	public Map<String, String> lumen$keys() {
		return lumen$keys != null ? lumen$keys : new HashMap<>();
	}
}
