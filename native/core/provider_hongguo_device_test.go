package core

import (
	"context"
	"net/http"
	"strconv"
	"testing"
)

func hongguoDeviceFixture(t *testing.T, rejected map[string]bool, registerFails bool) (*Downloader, *[]string) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.String() == hongguoDeviceRegisterURL+"?"+request.URL.RawQuery {
			registered++
			requests = append(requests, "register")
			if request.URL.Query().Get("device_id") != "" || request.Header.Get("X-Argus") != "" {
				t.Error("device registration leaked an old device or a signature")
			}
			if registerFails {
				return sourceFixtureResponse(request, http.StatusOK, `{"device_id":0,"install_id":0}`), nil
			}
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		device := request.URL.Query().Get("device_id")
		requests = append(requests, "detail@"+device)
		if rejected[device] {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
	})
	d.cfg.Retries = 2
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", false
	return d, &requests
}

func TestHongguoSignedRequestRegistersDeviceFirst(t *testing.T) {
	d, requests := hongguoDeviceFixture(t, nil, false)
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{}); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodGet, hongguoBookmallTabPath, nil, nil); err != nil {
		t.Fatal(err)
	}
	state := d.hongguoCatalogSnapshot()
	if !state.Registered || state.DeviceID != "1001" || state.InstallID != "10019" {
		t.Fatal("registered device was not kept", state)
	}
	if got := *requests; len(got) != 3 || got[0] != "register" || got[1] != "detail@1001" || got[2] != "detail@1001" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoRejectedDeviceIsReplacedAndRetried(t *testing.T) {
	d, requests := hongguoDeviceFixture(t, map[string]bool{"1001": true, "1002": true}, false)
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{}); err != nil {
		t.Fatal(err)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1003" || !state.Registered {
		t.Fatal("rejected device was not replaced", state)
	}
	want := []string{"register", "detail@1001", "register", "detail@1002", "register", "detail@1003"}
	if got := *requests; len(got) != len(want) {
		t.Fatal("unexpected request sequence", got)
	} else {
		for index := range want {
			if got[index] != want[index] {
				t.Fatal("unexpected request sequence", got)
			}
		}
	}
}

func TestHongguoTabRejectionKeepsDevice(t *testing.T) {
	d, requests := hongguoDeviceFixture(t, map[string]bool{"7": true}, false)
	d.cfg.Retries = 1
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodGet, hongguoBookmallTabPath, nil, nil); err == nil {
		t.Fatal("empty tab response became a success")
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" || state.Registered {
		t.Fatal("unsigned tab request changed the device", state)
	}
	if got := *requests; len(got) != 1 || got[0] != "detail@7" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoRegisterFailurePausesAndKeepsOldDevice(t *testing.T) {
	d, requests := hongguoDeviceFixture(t, nil, true)
	for range 2 {
		if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{}); err != nil {
			t.Fatal(err)
		}
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" || state.Registered {
		t.Fatal("failed registration changed the device", state)
	}
	if got := *requests; len(got) != 3 || got[0] != "register" || got[1] != "detail@7" || got[2] != "detail@7" {
		t.Fatal("registration was not paused after failure", got)
	}
}
