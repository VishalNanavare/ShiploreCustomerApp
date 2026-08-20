package com.shiplore.consumer.shiplore;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.shiplore/config")
                .setMethodCallHandler((call, result) -> {
                    if ("getMapsApiKey".equals(call.method)) {
                        try {
                            ApplicationInfo info = getPackageManager().getApplicationInfo(
                                    getPackageName(), PackageManager.GET_META_DATA);
                            String key = info.metaData != null
                                    ? info.metaData.getString("com.google.android.geo.API_KEY", "")
                                    : "";
                            result.success(key);
                        } catch (PackageManager.NameNotFoundException e) {
                            result.success("");
                        }
                    } else {
                        result.notImplemented();
                    }
                });
    }
}
