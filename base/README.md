This is a working guide on how to install Arch Linux with improved security which utilizes \
LUKS2 encrypted partition and how to set up Secure Boot and enroll TPM2. \
It is based on work of @schm1d and @joelmathewthomas, big thanks for their awesome guides. \
I tried to gather all the best things from them and modify so that it works as it should.\
## This implementation forces user to use a PIN to allow TPM to load the key, so that it is not vulnerable to cold boot attacks. \
Remember that physical brute force can be very effective to make you reveal your PIN.

