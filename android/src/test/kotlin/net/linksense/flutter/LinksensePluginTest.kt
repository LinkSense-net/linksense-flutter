package net.linksense.flutter

// Unit tests for the Android plugin bridge. JUnit 5 + Mockito-Kotlin.
//
// Compile-blocked until the native LinkSense Android SDK is on the
// build classpath — these tests import `net.linksense.sdk.*` directly
// (the same types `LinksensePlugin.kt` keys off). Pre-publish, the
// dependency in `android/build.gradle` is commented out, so `./gradlew
// test` will fail with `unresolved reference` until the SDK is wired
// via composite build or Maven publish. Once wired, the suite below
// runs without further changes.

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.linksense.sdk.LinkSenseError
import net.linksense.sdk.links.CreateLinkOptions
import net.linksense.sdk.links.FieldUpdate
import net.linksense.sdk.links.LinkMetadataValue
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify

class LinksensePluginTest {

    private lateinit var plugin: LinksensePlugin
    private lateinit var result: MethodChannel.Result

    @BeforeEach
    fun setUp() {
        plugin = LinksensePlugin()
        result = mock()
    }

    // MARK: - surfaceError

    @Test
    fun `surfaceError emits NOT_CONFIGURED code`() {
        plugin.invokeSurfaceError(LinkSenseError.NotConfigured, result)
        verify(result).error(eq("NOT_CONFIGURED"), anyOrNull(), anyOrNull())
    }

    @Test
    fun `surfaceError emits UNAUTHORIZED for Unauthorized`() {
        plugin.invokeSurfaceError(LinkSenseError.Unauthorized, result)
        verify(result).error(eq("UNAUTHORIZED"), anyOrNull(), anyOrNull())
    }

    @Test
    fun `surfaceError emits NOT_FOUND for NotFound`() {
        plugin.invokeSurfaceError(LinkSenseError.NotFound, result)
        verify(result).error(eq("NOT_FOUND"), anyOrNull(), anyOrNull())
    }

    @Test
    fun `surfaceError emits CUSTOM_PATH_EXISTS for CustomPathExists`() {
        plugin.invokeSurfaceError(LinkSenseError.CustomPathExists, result)
        verify(result).error(eq("CUSTOM_PATH_EXISTS"), anyOrNull(), anyOrNull())
    }

    @Test
    fun `surfaceError emits INVALID_INPUT with fieldErrors details`() {
        val fieldErrors = mapOf("name" to "too short", "metadata.tag" to "must be string")
        plugin.invokeSurfaceError(LinkSenseError.InvalidInput(fieldErrors), result)

        val detailsCaptor = argumentCaptor<Map<String, Any?>>()
        verify(result).error(eq("INVALID_INPUT"), anyOrNull(), detailsCaptor.capture())
        assertEquals(fieldErrors, detailsCaptor.firstValue["fieldErrors"])
    }

    @Test
    fun `surfaceError emits RATE_LIMITED with retryAfter details`() {
        plugin.invokeSurfaceError(LinkSenseError.RateLimited(42), result)
        val detailsCaptor = argumentCaptor<Map<String, Any?>>()
        verify(result).error(eq("RATE_LIMITED"), anyOrNull(), detailsCaptor.capture())
        assertEquals(42, detailsCaptor.firstValue["retryAfter"])
    }

    // MARK: - createOptionsFrom

    @Test
    fun `createOptionsFrom returns null when name missing`() {
        val options = plugin.invokeCreateOptionsFrom(mapOf("slug" to "x"))
        assertNull(options)
    }

    @Test
    fun `createOptionsFrom maps all fields`() {
        val raw = mapOf(
            "name" to "Promo",
            "slug" to "promo",
            "desktop_url" to "https://example.com",
            "tags" to listOf("tag-a"),
            "metadata" to mapOf("count" to 1),
            "ios_clipboard_enabled" to true,
            "ios_fallback_url" to "https://ios",
            "android_fallback_url" to "https://android",
            "og_title" to "Title",
            "og_description" to "Desc",
            "og_image_url" to "https://img",
        )
        val options = plugin.invokeCreateOptionsFrom(raw)!!
        assertEquals("Promo", options.name)
        assertEquals("promo", options.slug)
        assertEquals("https://example.com", options.desktopUrl)
        assertEquals(listOf("tag-a"), options.tags)
        assertEquals("https://ios", options.iosFallbackUrl)
        assertEquals(true, options.iosClipboardEnabled)
    }

    // MARK: - updateOptionsFrom FieldUpdate semantics

    @Test
    fun `updateOptionsFrom marks absent fields as FieldUpdate Absent`() {
        val options = plugin.invokeUpdateOptionsFrom(emptyMap<String, Any?>())
        assertTrue(options.desktopUrl is FieldUpdate.Absent)
        assertTrue(options.ogTitle is FieldUpdate.Absent)
        assertTrue(options.metadata is FieldUpdate.Absent)
    }

    @Test
    fun `updateOptionsFrom maps explicit null to FieldUpdate Clear`() {
        val options = plugin.invokeUpdateOptionsFrom(mapOf(
            "desktop_url" to null,
            "og_title" to null,
        ))
        assertTrue(options.desktopUrl is FieldUpdate.Clear)
        assertTrue(options.ogTitle is FieldUpdate.Clear)
    }

    @Test
    fun `updateOptionsFrom maps value to FieldUpdate Set`() {
        val options = plugin.invokeUpdateOptionsFrom(mapOf(
            "desktop_url" to "https://new.example",
            "og_title" to "New title",
        ))
        val desktop = options.desktopUrl as FieldUpdate.Set<*>
        assertEquals("https://new.example", desktop.value)
        val og = options.ogTitle as FieldUpdate.Set<*>
        assertEquals("New title", og.value)
    }

    // MARK: - toMetadataValue conversion

    @Test
    fun `toMetadataValue handles primitives`() {
        assertEquals(LinkMetadataValue.StringValue("hi"), plugin.invokeToMetadataValue("hi"))
        assertEquals(LinkMetadataValue.BoolValue(true), plugin.invokeToMetadataValue(true))
        assertEquals(LinkMetadataValue.LongValue(42L), plugin.invokeToMetadataValue(42))
        assertEquals(LinkMetadataValue.LongValue(99L), plugin.invokeToMetadataValue(99L))
        assertEquals(LinkMetadataValue.DoubleValue(1.5), plugin.invokeToMetadataValue(1.5))
        assertEquals(LinkMetadataValue.Null, plugin.invokeToMetadataValue(null))
    }

    @Test
    fun `toMetadataValue handles nested map`() {
        val result = plugin.invokeToMetadataValue(mapOf("k" to "v"))!! as LinkMetadataValue.ObjectValue
        assertEquals(LinkMetadataValue.StringValue("v"), result.values["k"])
    }

    @Test
    fun `toMetadataValue handles list of mixed types`() {
        val result = plugin.invokeToMetadataValue(listOf("a", 1, true)) as LinkMetadataValue.ArrayValue
        assertEquals(3, result.values.size)
        assertEquals(LinkMetadataValue.StringValue("a"), result.values[0])
        assertEquals(LinkMetadataValue.LongValue(1L), result.values[1])
        assertEquals(LinkMetadataValue.BoolValue(true), result.values[2])
    }
}

// Test-only accessors. These use reflection to reach the private
// helpers inside LinksensePlugin without exposing them in production
// API surface. Each method is a thin trampoline — keeps the plugin's
// internal visibility tight.
private fun LinksensePlugin.invokeSurfaceError(error: Throwable, result: MethodChannel.Result) {
    val m = LinksensePlugin::class.java.getDeclaredMethod(
        "surfaceError", MethodChannel.Result::class.java, Throwable::class.java
    ).apply { isAccessible = true }
    m.invoke(this, result, error)
}

private fun LinksensePlugin.invokeCreateOptionsFrom(map: Map<*, *>): CreateLinkOptions? {
    val m = LinksensePlugin::class.java.getDeclaredMethod("createOptionsFrom", Map::class.java)
        .apply { isAccessible = true }
    @Suppress("UNCHECKED_CAST")
    return m.invoke(this, map) as CreateLinkOptions?
}

private fun LinksensePlugin.invokeUpdateOptionsFrom(map: Map<*, *>): net.linksense.sdk.links.UpdateLinkOptions {
    val m = LinksensePlugin::class.java.getDeclaredMethod("updateOptionsFrom", Map::class.java)
        .apply { isAccessible = true }
    return m.invoke(this, map) as net.linksense.sdk.links.UpdateLinkOptions
}

private fun LinksensePlugin.invokeToMetadataValue(value: Any?): LinkMetadataValue? {
    val m = LinksensePlugin::class.java.getDeclaredMethod("toMetadataValue", Any::class.java)
        .apply { isAccessible = true }
    return m.invoke(this, value) as LinkMetadataValue?
}

// Small mockito-kotlin matchers used above.
private fun anyOrNull(): String? = org.mockito.kotlin.anyOrNull()
private fun <T> eq(value: T): T = org.mockito.kotlin.eq(value)
