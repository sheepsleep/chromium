// Copyright (c) 2009 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_PASSWORD_MANAGER_PASSWORD_STORE_MAC_INTERNAL_H_
#define CHROME_BROWSER_PASSWORD_MANAGER_PASSWORD_STORE_MAC_INTERNAL_H_

#include <Security/Security.h>

#include <string>
#include <vector>

#include "base/time.h"
#include "chrome/browser/keychain_mac.h"

// Adapter that wraps a MacKeychain and provides interaction in terms of
// PasswordForms instead of Keychain items.
class MacKeychainPasswordFormAdapter {
 public:
  // Creates an adapter for |keychain|. This class does not take ownership of
  // |keychain|, so the caller must make sure that the keychain outlives the
  // created object.
  explicit MacKeychainPasswordFormAdapter(MacKeychain* keychain);

  // Returns PasswordForms for each keychain entry matching |form|.
  // Caller is responsible for deleting the returned forms.
  std::vector<webkit_glue::PasswordForm*> PasswordsMatchingForm(
      const webkit_glue::PasswordForm& query_form);

  // Creates a new keychain entry from |form|, or updates the password of an
  // existing keychain entry if there is a collision. Returns true if a keychain
  // entry was successfully added/updated.
  bool AddLogin(const webkit_glue::PasswordForm& form);

 private:
  // Returns PasswordForms constructed from the given Keychain items.
  // Caller is responsible for deleting the returned forms.
  std::vector<webkit_glue::PasswordForm*> CreateFormsFromKeychainItems(
      const std::vector<SecKeychainItemRef>& items);

  // Searches |keychain| for all items usable for the given signon_realm, and
  // puts them in |items|. The caller is responsible for calling keychain->Free
  // on each of them when it is finished with them.
  std::vector<SecKeychainItemRef> MatchingKeychainItems(
      const std::string& signon_realm,
      webkit_glue::PasswordForm::Scheme scheme);

  // Changes the password for keychain_item to |password|; returns true if the
  // password was successfully changed.
  bool SetKeychainItemPassword(const SecKeychainItemRef& keychain_item,
                               const std::string& password);

  // Sets the creator code of keychain_item to creator_code; returns true if the
  // creator code was successfully set.
  bool SetKeychainItemCreatorCode(const SecKeychainItemRef& keychain_item,
                                  OSType creator_code);

  MacKeychain* keychain_;

  DISALLOW_COPY_AND_ASSIGN(MacKeychainPasswordFormAdapter);
};

namespace internal_keychain_helpers {

// Searches |keychain| for the specific keychain entry matching the given form,
// and returns it (or NULL if no match is found).
// The caller is responsible for calling keychain->Free on the returned item.
SecKeychainItemRef MatchingKeychainItem(const MacKeychain& keychain,
                                        const webkit_glue::PasswordForm& form);

// Sets the fields of |form| based on the keychain data from |keychain_item|.
// Fields that can't be determined from |keychain_item| will be unchanged.
//
// IMPORTANT: This function can cause the OS to trigger UI (to allow access to
// the keychain item if we aren't trusted for the item), and block until the UI
// is dismissed.
//
// If excessive prompting for access to other applications' keychain items
// becomes an issue, the password storage API will need to be refactored to
// allow the password to be retrieved later (accessing other fields doesn't
// require authorization).
bool FillPasswordFormFromKeychainItem(const MacKeychain& keychain,
                                      const SecKeychainItemRef& keychain_item,
                                      webkit_glue::PasswordForm* form);

// Returns true if the two given forms match based on signon_reaml, scheme, and
// username_value, and are thus suitable for merging (see MergePasswordForms).
// If this returns true, and path_matches is non-NULL, *path_matches will be set
// based on whether the full origin matches as well.
bool FormsMatchForMerge(const webkit_glue::PasswordForm& form_a,
                        const webkit_glue::PasswordForm& form_b,
                        bool* path_matches);

// Populates merged_forms by combining the password data from keychain_forms and
// the metadata from database_forms, removing used entries from the two source
// lists.
//
// On return, database_forms and keychain_forms will have only unused
// entries; for database_forms that means entries for which no corresponding
// password can be found (and which aren't blacklist entries), but for
// keychain_forms it's only entries we explicitly choose not to use (e.g.,
// blacklist entries from other browsers). Keychain entries that we have no
// database matches for will still end up in merged_forms, since they have
// enough information to be used as imported passwords.
void MergePasswordForms(std::vector<webkit_glue::PasswordForm*>* keychain_forms,
                        std::vector<webkit_glue::PasswordForm*>* database_forms,
                        std::vector<webkit_glue::PasswordForm*>* merged_forms);

}  // internal_keychain_helpers

#endif  // CHROME_BROWSER_PASSWORD_MANAGER_PASSWORD_STORE_MAC_INTERNAL_H_
