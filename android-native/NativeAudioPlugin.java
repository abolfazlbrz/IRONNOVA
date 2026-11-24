package com.ironnova.app;

import android.content.ClipData;
import android.content.Intent;
import android.database.Cursor;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.net.Uri;
import android.provider.OpenableColumns;

import androidx.activity.result.ActivityResult;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.IOException;

@CapacitorPlugin(name = "NativeAudio")
public class NativeAudioPlugin extends Plugin {
    private MediaPlayer player;
    private String currentUri = "";

    @PluginMethod
    public void pickAudioFiles(PluginCall call) {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("audio/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(call, intent, "handleAudioPicker");
    }

    @ActivityCallback
    private void handleAudioPicker(PluginCall call, ActivityResult result) {
        if (call == null) return;
        if (result == null || result.getResultCode() != android.app.Activity.RESULT_OK || result.getData() == null) {
            call.reject("انتخاب فایل لغو شد");
            return;
        }
        Intent data = result.getData();
        JSArray files = new JSArray();
        ClipData clip = data.getClipData();
        try {
            if (clip != null) {
                for (int i = 0; i < clip.getItemCount(); i++) {
                    Uri uri = clip.getItemAt(i).getUri();
                    addUriToResult(uri, files);
                }
            } else if (data.getData() != null) {
                addUriToResult(data.getData(), files);
            }
            JSObject response = new JSObject();
            response.put("files", files);
            call.resolve(response);
        } catch (Exception ex) {
            call.reject("خواندن فهرست فایل‌ها ناموفق بود: " + ex.getMessage());
        }
    }

    private void addUriToResult(Uri uri, JSArray files) throws Exception {
        if (uri == null) return;
        try {
            getContext().getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException ignored) { }
        String name = uri.getLastPathSegment() == null ? "آهنگ" : uri.getLastPathSegment();
        long size = -1;
        Cursor cursor = null;
        try {
            cursor = getContext().getContentResolver().query(uri, null, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                int sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE);
                if (nameIndex >= 0) name = cursor.getString(nameIndex);
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex);
            }
        } finally {
            if (cursor != null) cursor.close();
        }
        JSObject item = new JSObject();
        item.put("uri", uri.toString());
        item.put("name", name);
        item.put("size", size);
        item.put("mimeType", getContext().getContentResolver().getType(uri));
        files.put(item);
    }

    @PluginMethod
    public void play(PluginCall call) {
        String uriValue = call.getString("uri");
        if (uriValue == null || uriValue.trim().isEmpty()) {
            call.reject("مسیر آهنگ معتبر نیست");
            return;
        }
        releasePlayer();
        currentUri = uriValue;
        try {
            player = new MediaPlayer();
            player.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build());
            player.setOnPreparedListener(mp -> {
                mp.start();
                JSObject state = new JSObject();
                state.put("duration", mp.getDuration());
                state.put("position", mp.getCurrentPosition());
                state.put("isPlaying", mp.isPlaying());
                call.resolve(state);
            });
            player.setOnCompletionListener(mp -> notifyListeners("ended", new JSObject()));
            player.setOnErrorListener((mp, what, extra) -> {
                JSObject error = new JSObject();
                error.put("what", what);
                error.put("extra", extra);
                notifyListeners("audioError", error);
                return true;
            });
            player.setDataSource(getContext(), Uri.parse(uriValue));
            player.prepareAsync();
        } catch (IOException | IllegalArgumentException ex) {
            releasePlayer();
            call.reject("پخش این فایل روی دستگاه ممکن نشد: " + ex.getMessage());
        }
    }

    @PluginMethod
    public void pause(PluginCall call) {
        if (player != null && player.isPlaying()) player.pause();
        call.resolve(getPlayerState());
    }

    @PluginMethod
    public void resume(PluginCall call) {
        if (player == null) {
            call.reject("ابتدا یک آهنگ انتخاب کن");
            return;
        }
        try {
            if (!player.isPlaying()) player.start();
            call.resolve(getPlayerState());
        } catch (IllegalStateException ex) {
            call.reject("ادامه پخش ممکن نشد");
        }
    }

    @PluginMethod
    public void seekTo(PluginCall call) {
        int position = call.getInt("position", 0);
        if (player == null) {
            call.reject("آهنگی در حال پخش نیست");
            return;
        }
        try {
            player.seekTo(Math.max(0, position));
            call.resolve(getPlayerState());
        } catch (IllegalStateException ex) {
            call.reject("جابجایی در آهنگ ممکن نشد");
        }
    }

    @PluginMethod
    public void getState(PluginCall call) {
        call.resolve(getPlayerState());
    }

    @PluginMethod
    public void stop(PluginCall call) {
        releasePlayer();
        currentUri = "";
        call.resolve();
    }

    private JSObject getPlayerState() {
        JSObject state = new JSObject();
        state.put("uri", currentUri);
        if (player == null) {
            state.put("duration", 0);
            state.put("position", 0);
            state.put("isPlaying", false);
        } else {
            try {
                state.put("duration", player.getDuration());
                state.put("position", player.getCurrentPosition());
                state.put("isPlaying", player.isPlaying());
            } catch (IllegalStateException ex) {
                state.put("duration", 0);
                state.put("position", 0);
                state.put("isPlaying", false);
            }
        }
        return state;
    }

    private void releasePlayer() {
        if (player != null) {
            try { player.stop(); } catch (IllegalStateException ignored) { }
            player.release();
            player = null;
        }
    }
}
