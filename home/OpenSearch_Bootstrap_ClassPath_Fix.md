# OpenSearch Bootstrap ClassPath Fix - FreeBSD

## Issue Summary

**Problem**: OpenSearch 3.0.0 fails to start on FreeBSD 14.2 with Java 21/24, throwing a `NoClassDefFoundError` for `org.opensearch.javaagent.bootstrap.AgentPolicy$AnyCanExit`.

**Root Cause**: The OpenSearch bootstrap process cannot find the `AgentPolicy` classes because the `opensearch-agent-bootstrap-3.0.0.jar` file is not included in the bootstrap classpath during startup.

## Error Details

```
java.lang.NoClassDefFoundError: org/opensearch/javaagent/bootstrap/AgentPolicy$AnyCanExit
    at org.opensearch.bootstrap.Security.configure(Security.java:163)
    at org.opensearch.bootstrap.Bootstrap.setup(Bootstrap.java:238)
```

## System Configuration

- **OS**: FreeBSD 14.2-RELEASE-p1
- **OpenSearch Version**: 3.0.0
- **Java Versions Tested**: OpenJDK 17, 21, 24
- **Installation Method**: FreeBSD ports/pkg

## File Locations

- **Missing Class Location**: `/usr/local/lib/opensearch/agent/opensearch-agent-bootstrap-3.0.0.jar`
- **JVM Options File**: `/usr/local/etc/opensearch/jvm.options`
- **Service Configuration**: `/etc/rc.conf`

## Solution

Add the agent bootstrap JAR to the JVM boot classpath by modifying the JVM options:

```bash
# Add this line to /usr/local/etc/opensearch/jvm.options
echo "-Xbootclasspath/a:/usr/local/lib/opensearch/agent/opensearch-agent-bootstrap-3.0.0.jar" | sudo tee -a /usr/local/etc/opensearch/jvm.options
```

## Step-by-Step Fix

1. **Verify the issue**:
   ```bash
   sudo service opensearch start
   sudo service opensearch status  # Should show "not running"
   ```

2. **Confirm the missing class exists**:
   ```bash
   jar -tf /usr/local/lib/opensearch/agent/opensearch-agent-bootstrap-3.0.0.jar | grep AgentPolicy
   ```
   Should show:
   ```
   org/opensearch/javaagent/bootstrap/AgentPolicy$AnyCanExit.class
   org/opensearch/javaagent/bootstrap/AgentPolicy$CallerCanExit.class
   org/opensearch/javaagent/bootstrap/AgentPolicy$NoneCanExit.class
   org/opensearch/javaagent/bootstrap/AgentPolicy.class
   ```

3. **Apply the fix**:
   ```bash
   echo "-Xbootclasspath/a:/usr/local/lib/opensearch/agent/opensearch-agent-bootstrap-3.0.0.jar" | sudo tee -a /usr/local/etc/opensearch/jvm.options
   ```

4. **Start OpenSearch**:
   ```bash
   sudo service opensearch start
   sudo service opensearch status  # Should show "running"
   ```

## Why This Works

- The `AgentPolicy` classes are required during the early bootstrap phase when `Security.configure()` is called
- These classes are packaged in `opensearch-agent-bootstrap-3.0.0.jar` but not included in the default classpath
- Adding the JAR to the boot classpath (`-Xbootclasspath/a:`) makes these classes available during JVM initialization
- The `/a:` suffix appends to the boot classpath rather than prepending

## Alternative Solutions (if the primary fix doesn't work)

1. **Java Agent approach**:
   ```bash
   echo "-javaagent:/usr/local/lib/opensearch/agent/opensearch-agent-bootstrap-3.0.0.jar" | sudo tee -a /usr/local/etc/opensearch/jvm.options
   ```

2. **System property to disable agent policy**:
   ```bash
   echo "-Dopensearch.security.agent.policy.disabled=true" | sudo tee -a /usr/local/etc/opensearch/jvm.options
   ```

## Additional Notes

- This issue appears to be specific to the FreeBSD port of OpenSearch 3.0.0
- The problem occurs with all tested Java versions (17, 21, 24)
- OpenSearch 3.0.0 was compiled with Java 21+ (class file version 65.0)
- The fix is persistent across restarts and upgrades
- No security implications - we're just making existing OpenSearch classes available during bootstrap

## Verification

After applying the fix, verify OpenSearch is working:

```bash
# Check service status
sudo service opensearch status

# Check if OpenSearch is responding
curl -X GET "localhost:9200/"

# Check logs for any issues
sudo tail -f /var/log/opensearch/opensearch.log
```

## Prevention

When upgrading OpenSearch in the future, check if this line still exists in the JVM options file:
```bash
sudo grep "Xbootclasspath" /usr/local/etc/opensearch/jvm.options
```

If missing after an upgrade, re-add the line using the same command from step 3.