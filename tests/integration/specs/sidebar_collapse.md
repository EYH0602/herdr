# Test: Sidebar collapse and expand

## Steps

1. Press `n` to create a workspace named `test`
2. Read the screen and verify the expanded sidebar shows the full workspace name `test`
3. Press prefix (ctrl+s), then `b` to collapse the sidebar
4. Read the screen and verify:
   - The sidebar is now narrow (just numbers and state dots, no workspace name visible)
   - The `»` expand icon is visible at the bottom of the sidebar
   - The terminal pane takes up more horizontal space
5. Press prefix (ctrl+s), then `b` again to expand
6. Verify the full workspace name `test` is visible again in the sidebar
