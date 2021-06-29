## This series

Starting out looking at exit signals and OTP process death has turned into a small series of posts, including this one. These are:

* [The many and varied ways to kill an OTP Process]({% post_url 2021-05-31-the-many-and-varied-ways-to-kill-an-otp-process %}): investigation of different ways to cause (or fail to cause) a process to exit.

* [What happens when a linked process dies]({% post_url 2021-06-08-what-happens-when-a-linked-process-dies %}): the impact of a process exiting on processes that are linked to it, excluding OTP processes with a parent/child relationship.

* [Death, Children, and OTP]({% post_url 2021-06-28-death-children-and-otp %}): the impact on an OTP process when
the process that spawned it (its _parent_) exits, particularly when the child is trapping exits.