"""Drives docs/play.html in Safari: every sample, twice over, and fails on the first Run that does not compile and run.

    python tests/play/safari.py [BASE_URL]      BASE_URL defaults to http://localhost:8000
"""
import sys
import time

from selenium import webdriver
from selenium.webdriver.common.by import By

base = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
samples = ["hello", "strings", "squares", "sort", "regex", "json", "sha256", "math"] * 2

driver = webdriver.Safari()
driver.set_script_timeout(120)
failed = []
try:
    driver.get(base + "/play.html?debug")
    print("Safari", driver.capabilities.get("browserVersion"), flush=True)
    run = driver.find_element(By.ID, "run")
    deadline = time.time() + 120
    while not run.is_enabled() and time.time() < deadline:
        time.sleep(0.5)
    print(driver.find_element(By.ID, "status").text, flush=True)
    for name in samples:
        driver.execute_script(
            "const s = document.getElementById('sample'); s.value = arguments[0]; s.dispatchEvent(new Event('change'))", name)
        time.sleep(1)
        run.click()
        deadline = time.time() + 60
        time.sleep(0.5)
        while not run.is_enabled() and time.time() < deadline:
            time.sleep(0.5)
        status = driver.find_element(By.ID, "status").text
        out = driver.find_element(By.ID, "out").text
        ok = status.startswith("Compiled") and "Exit status 0" in status and driver.find_element(By.ID, "download").is_displayed()
        print(("ok   " if ok else "FAIL ") + name + ": " + status, flush=True)
        if not ok:
            print(out, flush=True)
            failed.append(name)
finally:
    driver.quit()
sys.exit(1 if failed else 0)
